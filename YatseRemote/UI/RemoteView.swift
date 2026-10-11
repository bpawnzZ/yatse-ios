import SwiftUI

struct RemoteView: View {
    let host: Host
    @StateObject private var model: AppModel

    @State private var scrubSeconds: Double?
    @State private var volumeDraft: Double?
    @State private var showingLibrary = false
    @State private var showingQueue = false
    @State private var showingKeyboard = false

    init(host: Host, password: String) {
        self.host = host
        _model = StateObject(wrappedValue: AppModel(host: host, password: password))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                statusBar
                nowPlaying
                transport
                scrubber
                trackControls
                dpad
                navigationKeys
                bottomRow
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
        .navigationTitle(host.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !host.macAddress.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await model.wake() }
                    } label: {
                        Image(systemName: "power")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingQueue = true } label: {
                    Image(systemName: "list.bullet")
                }
            }
        }
        .task { await model.connect() }
        .onDisappear { model.disconnect() }
        .sheet(isPresented: $showingLibrary) { LibraryView(model: model) }
        .sheet(isPresented: $showingQueue) { QueueSheet(model: model) }
        .sheet(isPresented: $showingKeyboard) { TextEntrySheet(model: model) }
    }

    // MARK: Sections

    private var statusBar: some View {
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

    private var nowPlaying: some View {
        HStack(spacing: 12) {
            ArtworkImage(
                url: Artwork.poster(for: model.item?.art ?? [:], thumbnail: model.item?.thumbnail ?? ""),
                username: host.username,
                password: model.password,
                size: 68
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(model.item?.title.isEmpty == false
                     ? (model.item?.title ?? "")
                     : (model.item?.label ?? "Nothing playing"))
                    .font(.headline)
                    .lineLimit(2)
                let subtitle = model.item?.subtitleLine ?? ""
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var transport: some View {
        HStack(spacing: 18) {
            RemoteButton(systemImage: "backward.fill", size: 46) { await model.skip("previous") }
            RemoteButton(
                systemImage: model.isPlaying ? "pause.fill" : "play.fill",
                size: 62
            ) { await model.togglePlayPause() }
            RemoteButton(systemImage: "stop.fill", size: 46) { await model.stopPlayback() }
            RemoteButton(systemImage: "forward.fill", size: 46) { await model.skip("next") }
        }
    }

    private var scrubber: some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(
                    get: { scrubSeconds ?? model.positionSeconds },
                    set: { scrubSeconds = $0 }
                ),
                in: 0...max(model.durationSeconds, 1)
            ) { editing in
                guard !editing, let target = scrubSeconds else { return }
                scrubSeconds = nil
                Task { await model.seek(toSeconds: target) }
            }

            HStack {
                Text(Self.timeText(scrubSeconds ?? model.positionSeconds))
                Spacer()
                Text(Self.timeText(model.durationSeconds))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var trackControls: some View {
        HStack(spacing: 10) {
            TinyButton(systemImage: "shuffle", isOn: model.properties?.shuffled == true) {
                await model.toggleShuffle()
            }
            TinyButton(systemImage: "repeat", isOn: (model.properties?.repeatMode ?? "off") != "off") {
                await model.cycleRepeat()
            }
            TinyButton(systemImage: "captions.bubble") { await model.cycleSubtitle() }
            TinyButton(systemImage: "waveform") { await model.cycleAudioStream() }

            Spacer()

            Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .frame(width: 24)

            Slider(
                value: Binding(
                    get: { volumeDraft ?? Double(model.volume) },
                    set: { volumeDraft = $0 }
                ),
                in: 0...100
            ) { editing in
                guard !editing, let target = volumeDraft else { return }
                volumeDraft = nil
                Task { await model.setVolume(Int(target)) }
            }
            .frame(maxWidth: 140)

            Button {
                Task { await model.toggleMute() }
            } label: {
                Text("Mute").font(.caption)
            }
        }
    }

    private var dpad: some View {
        VStack(spacing: 8) {
            RemoteButton(systemImage: "arrowtriangle.up.fill", size: 52) { await model.key("up") }
            HStack(spacing: 8) {
                RemoteButton(systemImage: "arrowtriangle.left.fill", size: 52) { await model.key("left") }
                RemoteButton(systemImage: "circle.fill", size: 62) { await model.key("select") }
                RemoteButton(systemImage: "arrowtriangle.right.fill", size: 52) { await model.key("right") }
            }
            RemoteButton(systemImage: "arrowtriangle.down.fill", size: 52) { await model.key("down") }
        }
    }

    private var navigationKeys: some View {
        HStack(spacing: 10) {
            TinyButton(systemImage: "arrow.uturn.backward") { await model.key("back") }
            TinyButton(systemImage: "house") { await model.key("home") }
            TinyButton(systemImage: "info.circle") { await model.key("info") }
            TinyButton(systemImage: "text.menu") { await model.key("contextmenu") }
            TinyButton(systemImage: "rectangle.on.rectangle") { await model.key("osd") }
        }
    }

    private var bottomRow: some View {
        HStack(spacing: 10) {
            WideButton(title: "Library", systemImage: "square.stack") { showingLibrary = true }
            WideButton(title: "Queue", systemImage: "list.number") { showingQueue = true }
            WideButton(title: "Keyboard", systemImage: "keyboard") { showingKeyboard = true }
        }
        .padding(.top, 4)
    }

    private static func timeText(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Buttons

struct RemoteButton: View {
    let systemImage: String
    let size: CGFloat
    let action: () async -> Void

    init(systemImage: String, size: CGFloat = 52, action: @escaping () async -> Void) {
        self.systemImage = systemImage
        self.size = size
        self.action = action
    }

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.36))
                .frame(width: size, height: size)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: size * 0.26))
        }
        .buttonStyle(.plain)
    }
}

struct TinyButton: View {
    let systemImage: String
    var isOn = false
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: systemImage)
                .font(.callout)
                .frame(width: 40, height: 34)
                .background(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                            in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }
}

struct WideButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
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
