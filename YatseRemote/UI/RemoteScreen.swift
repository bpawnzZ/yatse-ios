import SwiftUI

/// The Remote: one screen, no scrolling. A flat header with the host name and
/// power / cast / remote actions; a shortcut bar; volume and utility tile rows;
/// then the directional pad, which expands to fill every point left on the
/// screen, with a bare Back control and the touchpad toggle beneath it.
///
/// Every colour comes from the active `RemoteTheme`, so the blue and dark
/// themes differ only in tokens. While something is playing the current item's
/// artwork is the blurred background and the tiles go translucent, letting the
/// artwork read through.
struct RemoteScreen: View {
    @ObservedObject var model: AppModel
    let onOpenDrawer: () -> Void
    let onSelect: (ShellDestination) -> Void

    @Environment(\.remoteTheme) private var theme

    @State private var showingKeyboard = false
    @State private var showingCastNotice = false
    @State private var touchpadEnabled = false
    @State private var pendingPower: PowerAction?

    /// Height reserved below the pad for the Back / touchpad row.
    private static let bottomRowHeight: CGFloat = 56
    /// Side of a volume or utility tile. Above the 44pt tap-target floor.
    private static let smallTile: CGFloat = 54
    /// Gap between D-pad tiles; uniform, so the pad stays a tight plus.
    private static let padGap: CGFloat = 6

    private enum PowerAction: String, Identifiable {
        case suspend, reboot, shutdown

        var id: String { rawValue }

        var title: String {
            switch self {
            case .suspend: return "Suspend"
            case .reboot: return "Reboot"
            case .shutdown: return "Shut down"
            }
        }

        var method: String {
            switch self {
            case .suspend: return "System.Suspend"
            case .reboot: return "System.Reboot"
            case .shutdown: return "System.Shutdown"
            }
        }
    }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            artworkBackground

            VStack(spacing: 14) {
                header
                statusLine
                shortcutStrip
                volumeRow
                utilityRow
                controlPad
                    .frame(maxHeight: .infinity)

                if let error = model.lastError {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                        Text(error)
                    }
                    .font(.caption)
                    .foregroundStyle(theme.icon)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingKeyboard) { TextEntrySheet(model: model) }
        .alert("Casting", isPresented: $showingCastNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Casting to another device is not available in this build.")
        }
        .confirmationDialog(
            "Host power",
            isPresented: Binding(
                get: { pendingPower != nil },
                set: { if !$0 { pendingPower = nil } }
            ),
            presenting: pendingPower
        ) { action in
            Button(action.title, role: .destructive) {
                Task { await model.send(action.method) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text("\(action.title) the media centre?")
        }
    }

    // MARK: Header

    /// Flat and plain: the hamburger, the title, then power / cast / remote,
    /// with no circular button backgrounds and no pill container.
    private var header: some View {
        HStack(spacing: 10) {
            headerButton("line.3.horizontal", label: "Open menu", action: onOpenDrawer)

            Text(model.host.displayName)
                .font(.headline)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            powerMenu
            headerButton("airplayvideo", label: "Cast") { showingCastNotice = true }
            Image(systemName: "av.remote")
                .font(.title3)
                .frame(width: 44, height: 44)
                .accessibilityLabel("Remote")
        }
        .foregroundStyle(theme.icon)
    }

    private func headerButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var powerMenu: some View {
        Menu {
            if !model.host.macAddress.isEmpty {
                Button { Task { await model.wake() } } label: {
                    Label("Wake", systemImage: "power")
                }
            }
            Button { pendingPower = .suspend } label: {
                Label("Suspend", systemImage: "moon")
            }
            Button { pendingPower = .reboot } label: {
                Label("Reboot", systemImage: "arrow.clockwise")
            }
            Button { pendingPower = .shutdown } label: {
                Label("Shut down", systemImage: "power")
            }
        } label: {
            Image(systemName: "power")
                .font(.title3)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Power")
    }

    // MARK: Connection state

    /// Shown only when it carries information — while connecting, or after a
    /// failure. The connected state says nothing: the green dot and the version
    /// string are gone from it, but the logic behind them is unchanged.
    @ViewBuilder
    private var statusLine: some View {
        if !model.status.isConnected {
            HStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.caption2)
                Text(model.status.label)
                    .font(.caption)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.icon.opacity(0.85))
        }
    }

    // MARK: Rows

    /// Icons only, on one flat bar, evenly spread. The visible labels are gone
    /// but each button keeps its accessibility label.
    private var shortcutStrip: some View {
        HStack(spacing: 0) {
            ForEach(RemoteShortcut.allCases) { shortcut in
                Button {
                    activate(shortcut)
                } label: {
                    Image(systemName: shortcut.systemImage)
                        .font(.title3)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(shortcut.title)
            }
        }
        .foregroundStyle(theme.icon)
        .background(theme.navBarFill)
    }

    /// Three small tiles, centred as a group rather than stretched edge to edge.
    private var volumeRow: some View {
        HStack(spacing: 10) {
            smallTile("speaker.wave.1.fill", label: "Volume down") {
                await model.stepVolume(by: -AppModel.volumeStep)
            }
            smallTile(model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                      label: model.muted ? "Unmute" : "Mute") {
                await model.toggleMute()
            }
            smallTile("speaker.wave.3.fill", label: "Volume up") {
                await model.stepVolume(by: AppModel.volumeStep)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// Five square tiles, each in an equal share of the row so the set spreads
    /// evenly without the tiles themselves being stretched. Back lives at the
    /// bottom of the pad now, not here.
    private var utilityRow: some View {
        HStack(spacing: 0) {
            utilityTile("captions.bubble", label: "Subtitles") { await model.cycleSubtitle() }
            utilityTile("arrow.up.left.and.arrow.down.right", label: "Fullscreen") {
                await model.toggleFullscreen()
            }
            utilityTile("info.circle", label: "Info") { await model.key("info") }
            utilityTile("keyboard", label: "Keyboard") { showingKeyboard = true }
            utilityTile("list.bullet", label: "Menu") { await model.key("contextmenu") }
        }
    }

    private func smallTile(_ symbol: String, label: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            tileLabel(symbol)
        }
        .buttonStyle(ThemeTileButtonStyle(theme: theme))
        .accessibilityLabel(label)
    }

    private func utilityTile(_ symbol: String, label: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            tileLabel(symbol)
        }
        .buttonStyle(ThemeTileButtonStyle(theme: theme))
        .accessibilityLabel(label)
        .frame(maxWidth: .infinity)
    }

    private func tileLabel(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(theme.icon)
            .frame(width: Self.smallTile, height: Self.smallTile)
            .contentShape(Rectangle())
    }

    // MARK: Directional pad

    private var controlPad: some View {
        GeometryReader { geo in
            let side = ControlPadMetrics.side(in: geo.size, reserved: Self.bottomRowHeight)
            VStack(spacing: 8) {
                if touchpadEnabled {
                    TouchpadSurface(model: model)
                        .frame(maxWidth: .infinity)
                        .frame(height: side)
                } else {
                    padGrid(side: side)
                }

                HStack {
                    backButton
                    Spacer()
                    touchpadToggle
                }
                .frame(height: Self.bottomRowHeight - 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    /// A plus of equally sized tiles with one uniform gap, so the grid measures
    /// exactly `side` across: three tiles and two gaps.
    private func padGrid(side: CGFloat) -> some View {
        let tile = max((side - 2 * Self.padGap) / 3, 0)
        return VStack(spacing: Self.padGap) {
            HStack(spacing: Self.padGap) {
                Color.clear.frame(width: tile, height: tile)
                dpadButton("chevron.up", label: "Up", tile: tile) { await model.key("up") }
                Color.clear.frame(width: tile, height: tile)
            }
            HStack(spacing: Self.padGap) {
                dpadButton("chevron.left", label: "Left", tile: tile) { await model.key("left") }
                selectButton(tile: tile)
                dpadButton("chevron.right", label: "Right", tile: tile) { await model.key("right") }
            }
            HStack(spacing: Self.padGap) {
                Color.clear.frame(width: tile, height: tile)
                dpadButton("chevron.down", label: "Down", tile: tile) { await model.key("down") }
                Color.clear.frame(width: tile, height: tile)
            }
        }
    }

    /// Thin-stroke chevrons in the accent colour, on the same tile as select.
    private func dpadButton(_ symbol: String, label: String, tile: CGFloat,
                            action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: max(tile * 0.34, 14), weight: .light))
                .foregroundStyle(theme.accent)
                .frame(width: tile, height: tile)
                .contentShape(Rectangle())
        }
        .buttonStyle(ThemeTileButtonStyle(theme: theme))
        .accessibilityLabel(label)
    }

    /// The centre is a tile like every other pad button, not a floating ring.
    private func selectButton(tile: CGFloat) -> some View {
        Button {
            Task { await model.key("select") }
        } label: {
            Circle()
                .strokeBorder(theme.icon, lineWidth: 2)
                .frame(width: max(tile * 0.42, 16), height: max(tile * 0.42, 16))
                .frame(width: tile, height: tile)
                .contentShape(Rectangle())
        }
        .buttonStyle(ThemeTileButtonStyle(theme: theme))
        .accessibilityLabel("Select")
    }

    /// A plain white arrow, no tile, level with the bottom of the pad.
    private var backButton: some View {
        Button {
            Task { await model.key("back") }
        } label: {
            Image(systemName: "arrow.left")
                .font(.title2)
                .foregroundStyle(theme.icon)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    /// A plain accent-coloured icon, no tile; the pad itself shows the state.
    private var touchpadToggle: some View {
        Button {
            touchpadEnabled.toggle()
        } label: {
            Image(systemName: "hand.tap")
                .font(.title2)
                .foregroundStyle(theme.accent)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Toggle touchpad")
        .accessibilityValue(touchpadEnabled ? "On" : "Off")
    }

    // MARK: Artwork background

    @ViewBuilder
    private var artworkBackground: some View {
        if let url = backgroundArtworkURL {
            ArtworkBackground(url: url, username: model.host.username, password: model.password)
        }
    }

    /// Nil unless a player is really active, so the backdrop follows playback
    /// rather than a cached item.
    private var backgroundArtworkURL: URL? {
        guard model.activePlayer != nil, let item = model.item else { return nil }
        if !item.fanart.isEmpty, let url = Artwork.url(item.fanart) { return url }
        return Artwork.poster(for: item.art, thumbnail: item.thumbnail)
    }

    private func activate(_ shortcut: RemoteShortcut) {
        if let destination = shortcut.destination {
            onSelect(destination)
        } else {
            Task { await model.openInKodi(window: "Pictures") }
        }
    }
}

/// The square the directional pad can occupy within a region, keeping it a
/// square so the arrows and select stay circular, and never letting it overflow
/// the space or go negative. Pure so the one non-obvious number in the Remote's
/// layout is unit-testable without a running view.
enum ControlPadMetrics {
    /// The side of the pad that fits in `available` leaving `reserved` points
    /// beneath it (the Back / touchpad row).
    static func side(in available: CGSize, reserved: CGFloat = 0) -> CGFloat {
        let headroom = available.height - reserved
        return max(min(available.width, headroom), 0)
    }
}

// MARK: - Sheets

struct QueueSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(model.playlist.enumerated()), id: \.offset) { index, entry in
                    Button {
                        Task { await model.playlistJump(to: index) }
                    } label: {
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)
                            MediaRow(item: entry, username: model.host.username, password: model.password)
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { await model.playlistRemove(at: index) }
                        } label: {
                            Label("Remove", systemImage: "minus.circle")
                        }
                    }
                }

                if model.playlist.isEmpty {
                    Text("The queue is empty.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await model.send("Playlist.Clear", ["playlistid": model.playlistid ?? 0])
                            await model.loadPlaylist()
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(model.playlist.isEmpty)
                }
            }
            .task { await model.loadPlaylist() }
        }
    }
}

struct TextEntrySheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Send to Kodi") {
                    TextField("Text", text: $text)
                        .focused($isFocused)
                        .autocorrectionDisabled()
                        .onSubmit { send() }
                }
            }
            .navigationTitle("Keyboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send", action: send)
                        .disabled(text.isEmpty)
                }
            }
            .onAppear { isFocused = true }
        }
    }

    private func send() {
        let value = text
        text = ""
        Task { await model.sendText(value) }
    }
}
