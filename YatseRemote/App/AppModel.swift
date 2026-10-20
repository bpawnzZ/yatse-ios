import Foundation

/// State and commands for one connected host.
///
/// Methods that touch `@Published` state are `@MainActor`; call them with
/// `await` from a `Task`, which SwiftUI button actions and `.task` already do.
final class AppModel: ObservableObject {
    enum Status: Equatable {
        case idle
        case connecting
        case connected
        case failed(String)

        var label: String {
            switch self {
            case .idle: return "Not connected"
            case .connecting: return "Connecting…"
            case .connected: return "Connected"
            case .failed(let message): return message
            }
        }

        var isConnected: Bool { self == .connected }
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var activePlayer: ActivePlayer?
    @Published private(set) var item: PlayerItem?
    @Published private(set) var properties: PlayerProperties?
    /// True only while the box is showing fullscreen playback — the seek gate.
    @Published private(set) var playbackIsFullscreen = false
    @Published private(set) var playlist: [MediaItem] = []
    @Published private(set) var volume = 0
    @Published private(set) var muted = false
    @Published private(set) var serverName = ""
    @Published private(set) var serverVersion = ""
    @Published private(set) var lastError: String?

    let host: Host
    /// Kept so artwork requests can reuse the host credentials.
    let password: String
    private let client: KodiClient
    private var ticker: Task<Void, Never>?

    init(host: Host, password: String) {
        self.host = host
        self.password = password
        self.client = KodiClient(host: host, username: host.username, password: password)
    }

    /// Read-only probe surface for the connection self-check. The sheet drives
    /// `Diagnostics` through this so it issues the same authenticated calls the
    /// remote uses, rather than hand-rolling requests.
    var diagnosticsContext: DiagnosticsContext { DiagnosticsContext.kodi(client) }

    var isPlaying: Bool { properties?.isPlaying ?? false }
    var positionSeconds: Double { properties?.time?.totalSeconds ?? 0 }
    var durationSeconds: Double { properties?.totaltime?.totalSeconds ?? 0 }
    var playerid: Int? { activePlayer?.playerid }
    var playlistid: Int? { properties.map { $0.playlistid >= 0 ? $0.playlistid : 0 } }

    // MARK: Lifecycle

    @MainActor
    func connect() async {
        status = .connecting
        lastError = nil
        do {
            try await client.ping()
            let app = try await client.applicationProperties()
            serverName = app.name
            serverVersion = app.versionLabel
            volume = app.volume
            muted = app.muted
            status = .connected
            startEventStream()
            await refresh()
        } catch {
            status = .failed(error.localizedDescription)
            clearPlaybackState()
        }
        // Started whichever way the handshake went. A handshake that failed on a
        // timeout is usually transient, and the poll is what recovers it: with the
        // ticker skipped, the failure latched — nothing ever refreshed player state
        // again, so the mini-player could never appear, while every other call
        // still reached the host and the app looked connected.
        startTicker()
    }

    @MainActor
    func disconnect() {
        ticker?.cancel()
        ticker = nil
        client.stopEventStream()
        clearPlaybackState()
        status = .idle
    }

    /// Drops every cached playback value.
    ///
    /// Called from each path that means "nothing is playing here" — the active
    /// player list came back empty, the notification socket closed, a connect
    /// failed, or the session was disconnected. The mini-player's visibility is
    /// `activePlayer != nil`, so anything that leaves that value standing keeps
    /// the bar on screen over stale metadata; that was the stuck-bar bug.
    ///
    /// A *transient* poll failure deliberately does not come through here: one
    /// dropped request while the host is otherwise fine is better left showing a
    /// second-old value than blanking the bar and blinking it back.
    @MainActor
    private func clearPlaybackState() {
        activePlayer = nil
        item = nil
        properties = nil
        playbackIsFullscreen = false
    }

    @MainActor
    func wake() async {
        do {
            try host.wake()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: State

    /// `light` skips the playlist fetch — used by the 1 Hz progress ticker and
    /// by notification-driven refreshes.
    ///
    /// Gated on the host being active rather than on the status already saying
    /// connected: a status left failed by a handshake is one of the states this is
    /// here to fix, so refusing to poll in it is what made the failure permanent.
    /// `.idle` is the one status that means the user left this host, and it is
    /// never polled or revived.
    @MainActor
    func refresh(light: Bool = false) async {
        guard status != .idle else { return }
        do {
            let app = try await client.applicationProperties()
            volume = app.volume
            muted = app.muted

            // The host answered, so a failure left by the handshake is spent:
            // revive the status, and the event stream that failure skipped.
            if Self.revivesFromFailure(status) {
                status = .connected
                startEventStream()
            }

            let players = try await client.activePlayers()
            activePlayer = Self.resolvedPlayer(answer: players, previous: activePlayer)

            guard let active = activePlayer else {
                // Nothing is playing: drop the metadata the bar and the artwork
                // backdrop would otherwise keep showing.
                clearPlaybackState()
                if !light { playlist = [] }
                lastError = nil
                return
            }

            async let propertiesCall = client.playerProperties(playerid: active.playerid)
            async let itemCall = client.currentItem(playerid: active.playerid)
            async let fullscreenCall = client.isFullscreenVideo()
            properties = try await propertiesCall
            item = try await itemCall
            // A failed probe keeps the last answer rather than assuming the video
            // went windowed: sending navigation where the user expected a seek (or
            // the reverse) is worse than a gate one tick stale.
            playbackIsFullscreen = (try? await fullscreenCall) ?? playbackIsFullscreen
            if !light { await loadPlaylist() }
            lastError = nil
        } catch {
            // While the status is itself the failure, the status line already
            // carries this sentence — setting the caption too prints it twice on
            // the same screen.
            if status.isConnected { lastError = error.localizedDescription }
        }
    }

    @MainActor
    func loadPlaylist() async {
        do {
            playlist = try await client.playlistItems(playlistid: playlistid ?? 0)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Commands

    /// Send one command, optionally repeated. Each repeat is its own round trip, so
    /// the refresh happens once at the end: a five-step swipe should cost five key
    /// presses, not five key presses plus five state polls.
    @MainActor
    func send(_ method: String, _ params: [String: Any] = [:], times: Int = 1) async {
        do {
            // ponytail: one POST per repeat. Kodi's JSON-RPC does accept a batch
            // array in a single POST if a long flick ever measures as laggy; it
            // does not accept a repeat count on Input.ExecuteAction.
            for _ in 0..<max(1, times) {
                _ = try await client.call(method, params: params, as: IgnoreResult.self)
            }
            lastError = nil
            await refresh(light: true)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Remote-control action names recovered from the Yatse DEX
    /// (`Input.ExecuteAction` call sites).
    @MainActor
    func key(_ action: String, times: Int = 1) async {
        let sent = Self.actionForPlayback(action, seeking: isSeeking)
        await send("Input.ExecuteAction", ["action": sent], times: times)
    }

    /// Something is playing *and* the box is showing it fullscreen.
    var isSeeking: Bool { playerid != nil && playbackIsFullscreen }

    /// Fullscreen playback is the one context where Kodi reads the arrow keys as
    /// seeks, so left/right become the step actions there, and where the centre
    /// raises the controls bar instead of selecting.
    ///
    /// The escalation — 10s, then 30s, 1min, 3min, 5min as the presses repeat — is
    /// Kodi's own progressive jump, the same one it gives a keyboard, so the app
    /// sends the step action once per press and keeps no ladder of its own. (`left`
    /// and `right` are the *actions*, not the keys, which is why they navigate
    /// rather than seek: the keymap binds arrow keys to the step actions in
    /// Fullscreen video, and an action bypasses that binding.)
    ///
    /// The centre sends `osd`, which is what a keyboard's Enter sends on a playing
    /// video — there is no "show OSD" action, only this toggle. Once the bar is up,
    /// Kodi's current window becomes the OSD (**12901**, distinct from fullscreen
    /// video's 12005 — measured on this box), so `isSeeking` goes false by itself:
    /// the centre then activates the focused control and left/right navigate the
    /// bar, exactly as they should. The window id carries the state, so no second
    /// flag is needed to know whether the bar is already open.
    ///
    /// `up` and `down` keep their meaning everywhere, so this cannot strand
    /// navigation while a video plays on in the background.
    static func actionForPlayback(_ action: String, seeking: Bool) -> String {
        guard seeking else { return action }
        switch action {
        case TouchKey.left.rawValue: return "stepback"
        case TouchKey.right.rawValue: return "stepforward"
        case TouchKey.select.rawValue: return "osd"
        default: return action
        }
    }

    /// The `o` overlay: resolution, video and audio codec, and whether the decoder
    /// is hardware or software.
    ///
    /// Asked for whenever a player is active, and no more tightly than that. Kodi
    /// decides whether the overlay opens or closes: the action is a toggle handled by
    /// the dialog itself (`CGUIDialogPlayerProcessInfo::OnAction` → `Close()` when it
    /// receives `ACTION_PLAYER_PROCESS_INFO`), and the press is routed to whichever
    /// window has focus — the overlay, once it is up.
    ///
    /// The earlier gate ("fullscreen video window 12005") was the bug behind "pressing
    /// it again does nothing": opening the overlay moves the current window off 12005,
    /// so the second press never left the phone and the overlay had to be closed with
    /// Back. Do not narrow this again — a remote cannot know which window the box
    /// considers focused, and does not need to.
    @MainActor
    func showPlayerProcessInfo() async {
        guard let action = Self.playerInfoAction(playing: playerid != nil) else { return }
        await send("Input.ExecuteAction", ["action": action])
    }

    /// `ActionTranslator.cpp` maps **both** `codecinfo` and `playerprocessinfo` to
    /// `ACTION_PLAYER_PROCESS_INFO` — aliases for one overlay, which only exists while
    /// a player is running. Named once here rather than spelled at the call site, so a
    /// typo cannot become an invisible button sending a dead action.
    static func playerInfoAction(playing: Bool) -> String? {
        playing ? "playerprocessinfo" : nil
    }

    @MainActor
    func togglePlayPause() async {
        guard let playerid else { return }
        await send("Player.PlayPause", ["playerid": playerid])
    }

    @MainActor
    func stopPlayback() async {
        guard let playerid else { return }
        await send("Player.Stop", ["playerid": playerid])
    }

    @MainActor
    func skip(_ direction: String) async {
        guard let playerid else { return }
        await send("Player.GoTo", ["playerid": playerid, "to": direction])
    }

    @MainActor
    func seek(toSeconds seconds: Double) async {
        guard let playerid else { return }
        let percentage = durationSeconds > 0 ? (seconds / durationSeconds) * 100 : 0
        await send("Player.Seek", ["playerid": playerid, "value": ["percentage": percentage]])
    }

    @MainActor
    func setVolume(_ value: Int) async {
        let clamped = Self.clampedVolume(value)
        volume = clamped
        await send("Application.SetVolume", ["volume": clamped])
    }

    @MainActor
    func stepVolume(by delta: Int) async {
        await setVolume(volume + delta)
    }

    @MainActor
    func toggleFullscreen() async {
        await send("GUI.SetFullscreen", ["fullscreen": "toggle"])
    }

    /// Volume change per press of the remote's volume tiles.
    static let volumeStep = 5

    /// Clamp a volume to Kodi's 0–100 range. Pure so it is unit-testable.
    static func clampedVolume(_ value: Int) -> Int {
        min(max(value, 0), 100)
    }

    @MainActor
    func toggleMute() async {
        await send("Application.SetMute", ["mute": "toggle"])
    }

    @MainActor
    func cycleSubtitle() async {
        guard let playerid else { return }
        await send("Player.SetSubtitle", ["playerid": playerid, "subtitle": "next"])
    }

    @MainActor
    func cycleAudioStream() async {
        guard let playerid else { return }
        await send("Player.SetAudioStream", ["playerid": playerid, "stream": "next"])
    }

    /// Select an audio stream by its own `index` (not its position in the list).
    @MainActor
    func selectAudioStream(index: Int) async {
        guard let playerid else { return }
        await send("Player.SetAudioStream", ["playerid": playerid, "stream": index])
    }

    /// Select a subtitle stream by its own `index`.
    @MainActor
    func selectSubtitle(index: Int) async {
        guard let playerid else { return }
        await send("Player.SetSubtitle",
                   ["playerid": playerid, "subtitle": SubtitleSelection.stream(index).payloadValue])
    }

    /// Turn subtitles off for the current item.
    @MainActor
    func subtitlesOff() async {
        guard let playerid else { return }
        await send("Player.SetSubtitle",
                   ["playerid": playerid, "subtitle": SubtitleSelection.off.payloadValue])
    }

    @MainActor
    func setShuffle(_ on: Bool) async {
        guard let playerid else { return }
        await send("Player.SetShuffle", ["playerid": playerid, "shuffle": on])
    }

    @MainActor
    func toggleShuffle() async {
        await setShuffle(!(properties?.shuffled ?? false))
    }

    @MainActor
    func setRepeat(_ mode: RepeatMode) async {
        guard let playerid else { return }
        await send("Player.SetRepeat", ["playerid": playerid, "repeat": mode.rawValue])
    }

    @MainActor
    func cycleRepeat() async {
        await setRepeat(RepeatMode.from(properties?.repeatMode ?? "off").next)
    }

    /// Previous / next item in the queue.
    @MainActor
    func previous() async { await skip("previous") }

    @MainActor
    func next() async { await skip("next") }

    /// Relative seek for the overlay's rewind / forward controls. `step` is one
    /// of Kodi's step tokens (`smallbackward`, `smallforward`, …).
    @MainActor
    func stepSeek(_ step: String) async {
        guard let playerid else { return }
        await send("Player.Seek", ["playerid": playerid, "value": ["step": step]])
    }

    /// Advance the video zoom / aspect mode. Kodi exposes no video-stream list, so
    /// this is the `aspectratio` action; the action string is confirmed against
    /// the live server's action enum before shipping.
    @MainActor
    func cycleAspect() async {
        await key("aspectratio")
    }

    @MainActor
    func sendText(_ text: String) async {
        guard !text.isEmpty else { return }
        await send("Input.SendText", ["text": text, "done": true])
    }

    @MainActor
    func openInKodi(window: String) async {
        await send("GUI.ActivateWindow", ["window": window])
    }

    /// The host's own home screen — `Input.Home`, the method a remote's Home
    /// button sends, so it lands where the host's Home button and backing out of
    /// a library land. One call rather than a walk of Backs.
    ///
    /// Measured on the box: this moved it `10032 'Settings - Interface'` →
    /// `10000 'Home'`. The two calls that look equivalent are not —
    /// `GUI.ActivateWindow {"window": "Home"}` and `Input.ExecuteAction
    /// {"action": "home"}` both come back invalid-params, because `window` and
    /// `action` are enums and neither name is in them. Not verified over
    /// fullscreen playback: that would mean starting a video on Alpha's box.
    @MainActor
    func goToKodiHome() async {
        await send("Input.Home")
    }

    @MainActor
    func play(item payload: [String: Any]) async {
        // A Player.Open that lands while the previous film is still stopping fails
        // intermittently on the box, so a replacement is stop → 1.5 s → open. The
        // box is asked rather than reading `activePlayer`: the poll stops when the
        // app is backgrounded, and a stale nil is the exact bug being fixed. A
        // failed ask means "idle", which is the old behaviour, not a dead tap.
        let players = (try? await client.activePlayers()) ?? []
        if case .stopThenOpen(let playerid) = Self.replacement(for: players) {
            await send("Player.Stop", ["playerid": playerid])
            try? await Task.sleep(for: Self.replacePause)
        }
        await send("Player.Open", ["item": payload])
    }

    /// How long to let the box settle between stopping and opening. The desktop
    /// client uses the same number against the same box (`desktop-stop-before-play`).
    static let replacePause: Duration = .milliseconds(1500)

    /// What has to happen before `Player.Open`. Pure, so CI can check the rule with
    /// no box on the runner.
    enum PlaybackReplacement: Equatable {
        case immediate
        case stopThenOpen(playerid: Int)
    }

    /// Only a **video** player is stopped: that is the reported failure. A video
    /// takes the player from music without it, so stopping audio first would only
    /// add the wait to a path that already works.
    static func replacement(for players: [ActivePlayer]) -> PlaybackReplacement {
        guard let playing = players.first(where: { $0.isVideo }) else { return .immediate }
        return .stopThenOpen(playerid: playing.playerid)
    }

    @MainActor
    func playlistJump(to index: Int) async {
        guard let playerid else { return }
        await send("Player.GoTo", ["playerid": playerid, "to": index])
    }

    @MainActor
    func playlistRemove(at index: Int) async {
        await send("Playlist.Remove", ["playlistid": playlistid ?? 0, "position": index])
        await loadPlaylist()
    }

    // MARK: Library

    /// Installed add-ons, for the Addons screen.
    @MainActor
    func addons() async throws -> [Addon] {
        try await client.addons()
    }

    /// Enabling or disabling an add-on also ends any playback it owns on Kodi,
    /// so the player state is refreshed rather than assumed unchanged.
    @MainActor
    func setAddonEnabled(_ addon: Addon, enabled: Bool) async {
        do {
            try await client.setAddonEnabled(addonid: addon.addonid, enabled: enabled)
            lastError = nil
            await refresh(light: true)
        } catch {
            lastError = error.localizedDescription
        }
    }

    @MainActor
    func sources(media: String) async throws -> [MediaItem] {
        try await client.sources(media: media)
    }

    @MainActor
    func directory(_ path: String, media: String) async throws -> [MediaItem] {
        try await client.directory(path, media: media)
    }

    @MainActor
    func libraryPage(_ section: LibrarySection, offset: Int, pageSize: Int = 60) async throws
        -> (items: [MediaItem], total: Int) {
        let payload = try await client.list(
            method: section.method,
            params: [
                "properties": section.properties,
                "limits": ["start": offset, "end": offset + pageSize],
                "sort": ["method": section.sortMethod, "order": "ascending"],
            ]
        )
        return (section.items(from: payload), payload.limits?.total ?? 0)
    }

    @MainActor
    func children(of request: ChildrenRequest) async throws -> [MediaItem] {
        let payload = try await client.list(method: request.method, params: request.params)
        return request.items(from: payload)
    }

    // MARK: Internals

    private func startEventStream() {
        client.startEventStream { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if event == KodiClient.streamClosedEvent {
                    // The host stopped talking to us, so whatever the last poll
                    // saw is no longer known to be true. Without this the bar
                    // stayed up with stale artwork after Kodi quit or the
                    // network went away.
                    self.clearPlaybackState()
                    self.lastError = "Live updates stopped — pull to refresh or reopen the remote."
                } else {
                    // Player.OnPlay / OnPause / OnResume / OnStop all land here.
                    // A stop comes back with an empty player list, which is what
                    // takes the bar down.
                    await self.refresh(light: true)
                }
            }
        }
    }

    /// Kodi pushes no progress ticks, so the scrubber needs a poll while the
    /// remote is on screen.
    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                await self.refresh(light: true)
            }
        }
    }
}

/// What `activePlayer` should become after a poll. Pure so the rule the
/// stuck-bar bug broke is unit-testable without a host: an empty answer clears
/// even when something *was* playing, while a failed poll (`answer == nil`)
/// keeps the last good value so one dropped request does not blink the bar out.
/// Video wins when both a video and an audio player are active.
extension AppModel {
    static func resolvedPlayer(answer: [ActivePlayer]?, previous: ActivePlayer?) -> ActivePlayer? {
        guard let answer else { return previous }
        return answer.first(where: { $0.isVideo }) ?? answer.first
    }

    /// Whether a poll that succeeded should revive the status, and with it the
    /// event stream the handshake skipped.
    ///
    /// `.failed` is the half-connected state a timed-out handshake leaves behind:
    /// every other call still reaches the host, so a poll that answers proves the
    /// connection is fine and the failure is spent. `.idle` is a deliberate
    /// disconnect and must never be revived, and a poll that succeeds while
    /// already connected has nothing to do. Pure so the rule is unit-testable
    /// without a host.
    static func revivesFromFailure(_ status: Status) -> Bool {
        if case .failed = status { return true }
        return false
    }
}

/// Kodi's repeat mode, with the cycle the overlay's repeat control walks. Pure so
/// the off → all → one ordering is unit-tested without a host.
enum RepeatMode: String, CaseIterable {
    case off
    case all
    case one

    var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }

    /// Map a raw Kodi value; anything unrecognised is treated as off.
    static func from(_ raw: String) -> RepeatMode {
        RepeatMode(rawValue: raw) ?? .off
    }
}

/// What `Player.SetSubtitle`'s `subtitle` parameter should carry: the string
/// `"off"` to disable, or the stream's own `index` to select one. Pure so the
/// "off is not index 0" distinction is unit-tested.
enum SubtitleSelection: Equatable {
    case off
    case stream(Int)

    var payloadValue: Any {
        switch self {
        case .off: return "off"
        case .stream(let index): return index
        }
    }
}
