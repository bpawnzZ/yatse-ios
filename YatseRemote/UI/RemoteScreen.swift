import SwiftUI

/// The Remote: one screen, no scrolling. App bar with the host name and power /
/// cast / remote actions; a shortcut strip; volume and utility tile rows pinned
/// at the top; then the directional pad, which expands to fill every point left
/// on the screen, with a bare Back control and the touchpad toggle beneath it.
/// While something is playing the current item's artwork is the blurred
/// background and the tiles go translucent.
struct RemoteScreen: View {
    @ObservedObject var model: AppModel
    let onOpenDrawer: () -> Void
    let onSelect: (ShellDestination) -> Void

    @State private var showingKeyboard = false
    @State private var showingCastNotice = false
    @State private var touchpadEnabled = false
    @State private var pendingPower: PowerAction?

    /// Height reserved below the pad for the Back / touchpad row.
    private static let bottomRowHeight: CGFloat = 56

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
            artworkBackground

            VStack(spacing: 14) {
                statusLine
                shortcutStrip
                volumeRow
                utilityRow
                controlPad
                    .frame(maxHeight: .infinity)

                if let error = model.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .navigationTitle(model.host.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { onOpenDrawer() } label: { Image(systemName: "line.3.horizontal") }
                    .accessibilityLabel("Open menu")
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                powerMenu
                Button { showingCastNotice = true } label: { Image(systemName: "airplayvideo") }
                    .accessibilityLabel("Cast")
                Image(systemName: "av.remote")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Remote")
            }
        }
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

    // MARK: App bar

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
        }
        .accessibilityLabel("Power")
    }

    // MARK: Status

    private var statusLine: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.status.isConnected ? .green : .red)
                .frame(width: 8, height: 8)
            Text(model.status.isConnected
                 ? (model.serverName.isEmpty ? model.status.label : "\(model.serverName) \(model.serverVersion)")
                 : model.status.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
    }

    // MARK: Rows

    private var shortcutStrip: some View {
        HStack(spacing: 8) {
            ForEach(RemoteShortcut.allCases) { shortcut in
                Button {
                    activate(shortcut)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: shortcut.systemImage)
                            .font(.title3)
                        Text(shortcut.title)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(tileBackground, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var volumeRow: some View {
        HStack(spacing: 10) {
            tile("speaker.wave.1.fill") { await model.stepVolume(by: -AppModel.volumeStep) }
            tile(model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill") { await model.toggleMute() }
            tile("speaker.wave.3.fill") { await model.stepVolume(by: AppModel.volumeStep) }
        }
    }

    private var utilityRow: some View {
        HStack(spacing: 10) {
            tile("arrow.backward") { await model.key("back") }
            tile("arrow.up.left.and.arrow.down.right") { await model.toggleFullscreen() }
            tile("info.circle") { await model.key("info") }
            tile("keyboard") { showingKeyboard = true }
            tile("list.bullet") { await model.key("contextmenu") }
        }
    }

    private func tile(_ symbol: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: symbol)
                .font(.title3)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(tileBackground, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
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

    private func padGrid(side: CGFloat) -> some View {
        let cell = max(side, 0) / 3
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: cell, height: cell)
                dpadButton("arrowtriangle.up.fill", cell: cell) { await model.key("up") }
                Color.clear.frame(width: cell, height: cell)
            }
            HStack(spacing: 0) {
                dpadButton("arrowtriangle.left.fill", cell: cell) { await model.key("left") }
                selectButton(cell: cell)
                dpadButton("arrowtriangle.right.fill", cell: cell) { await model.key("right") }
            }
            HStack(spacing: 0) {
                Color.clear.frame(width: cell, height: cell)
                dpadButton("arrowtriangle.down.fill", cell: cell) { await model.key("down") }
                Color.clear.frame(width: cell, height: cell)
            }
        }
        .frame(width: max(side, 0), height: max(side, 0))
    }

    private func dpadButton(_ symbol: String, cell: CGFloat, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: max(cell * 0.4, 16)))
                .foregroundStyle(.tint)
                .frame(width: max(cell - 8, 0), height: max(cell - 8, 0))
                .background(tileBackground, in: RoundedRectangle(cornerRadius: 16))
                .frame(width: cell, height: cell)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func selectButton(cell: CGFloat) -> some View {
        Button {
            Task { await model.key("select") }
        } label: {
            Circle()
                .strokeBorder(.primary, lineWidth: 3)
                .frame(width: max(cell - 16, 0), height: max(cell - 16, 0))
                .contentShape(Circle())
                .frame(width: cell, height: cell)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select")
    }

    private var backButton: some View {
        Button {
            Task { await model.key("back") }
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.title2)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    private var touchpadToggle: some View {
        Button {
            touchpadEnabled.toggle()
        } label: {
            Image(systemName: "hand.tap")
                .font(.title3)
                .frame(width: 48, height: 48)
                .background(touchpadEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                            in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Toggle touchpad")
    }

    // MARK: Artwork background

    @ViewBuilder
    private var artworkBackground: some View {
        if let url = backgroundArtworkURL {
            ArtworkBackground(url: url, username: model.host.username, password: model.password)
        }
    }

    private var backgroundArtworkURL: URL? {
        guard model.activePlayer != nil, let item = model.item else { return nil }
        if !item.fanart.isEmpty, let url = Artwork.url(item.fanart) { return url }
        return Artwork.poster(for: item.art, thumbnail: item.thumbnail)
    }

    private var tileBackground: AnyShapeStyle {
        backgroundArtworkURL == nil ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.ultraThinMaterial)
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
