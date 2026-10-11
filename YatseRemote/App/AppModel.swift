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
            startTicker()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    @MainActor
    func disconnect() {
        ticker?.cancel()
        ticker = nil
        client.stopEventStream()
        status = .idle
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
    @MainActor
    func refresh(light: Bool = false) async {
        guard status.isConnected else { return }
        do {
            let app = try await client.applicationProperties()
            volume = app.volume
            muted = app.muted

            let players = try await client.activePlayers()
            let active = players.first(where: { $0.isVideo }) ?? players.first
            activePlayer = active

            guard let active else {
                item = nil
                properties = nil
                if !light { playlist = [] }
                lastError = nil
                return
            }

            async let propertiesCall = client.playerProperties(playerid: active.playerid)
            async let itemCall = client.currentItem(playerid: active.playerid)
            properties = try await propertiesCall
            item = try await itemCall
            if !light { await loadPlaylist() }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
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

    @MainActor
    func send(_ method: String, _ params: [String: Any] = [:]) async {
        do {
            _ = try await client.call(method, params: params, as: IgnoreResult.self)
            lastError = nil
            await refresh(light: true)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Remote-control action names recovered from the Yatse DEX
    /// (`Input.ExecuteAction` call sites).
    @MainActor
    func key(_ action: String) async {
        await send("Input.ExecuteAction", ["action": action])
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

    @MainActor
    func play(item payload: [String: Any]) async {
        await send("Player.Open", ["item": payload])
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
                    self.lastError = "Live updates stopped — pull to refresh or reopen the remote."
                } else {
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
