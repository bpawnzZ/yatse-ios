import SwiftUI

/// The full-screen Now Playing surface, opened from the mini-player. The current
/// item's artwork is a see-through backdrop under a translucent scrim; the seek
/// slider, transport row, repeat/shuffle, stream pickers, info and the queue sit
/// over it.
struct NowPlayingView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var seekTarget: Double = 0
    @State private var isSeeking = false
    @State private var showingInfo = false
    @State private var showingQueue = false

    @Environment(\.remoteTheme) private var theme

    private var contentColor: Color { theme.icon }

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 18) {
                header
                Spacer(minLength: 0)
                seekSection
                transportSection
                optionsSection
                Spacer(minLength: 0)
            }
            .padding()
        }
        .sheet(isPresented: $showingInfo) { NowPlayingInfoView(model: model) }
        .sheet(isPresented: $showingQueue) { QueueSheet(model: model) }
        .onAppear { seekTarget = model.positionSeconds }
        .onChange(of: model.positionSeconds) { _, value in
            if !isSeeking { seekTarget = value }
        }
    }

    // MARK: Backdrop

    @ViewBuilder
    private var backdrop: some View {
        if let url = backdropURL {
            ArtworkBackground(url: url, username: model.host.username, password: model.password)
        } else {
            theme.background.ignoresSafeArea()
        }
    }

    private var backdropURL: URL? {
        guard let item = model.item else { return nil }
        if !item.fanart.isEmpty, let url = Artwork.url(item.fanart) { return url }
        return Artwork.poster(for: item.art, thumbnail: item.thumbnail)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(contentColor.opacity(0.8))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)

            Button { showingInfo = true } label: {
                headerIcon("info.circle")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Info")

            Button { showingQueue = true } label: {
                headerIcon("list.bullet")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Queue")
        }
        .foregroundStyle(contentColor)
    }

    private func headerIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.title3)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    // MARK: Seek

    private var seekSection: some View {
        VStack(spacing: 4) {
            Slider(
                value: $seekTarget,
                in: 0...max(model.durationSeconds, 1),
                onEditingChanged: { editing in
                    isSeeking = editing
                    if !editing { Task { await model.seek(toSeconds: seekTarget) } }
                }
            )
            .tint(contentColor)
            .disabled(model.durationSeconds <= 0)

            HStack {
                Text(TimeText.mmss(seekTarget))
                Spacer()
                Text(TimeText.mmss(model.durationSeconds))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(contentColor.opacity(0.85))
        }
    }

    // MARK: Transport

    private var transportSection: some View {
        HStack(spacing: 14) {
            transport("backward.end.fill") { await model.previous() }
            transport("gobackward.10") { await model.stepSeek("smallbackward") }
            playPauseButton
            transport("goforward.10") { await model.stepSeek("smallforward") }
            transport("forward.end.fill") { await model.next() }
            transport("stop.fill") { await model.stopPlayback() }
        }
        .foregroundStyle(contentColor)
    }

    private var playPauseButton: some View {
        Button {
            Task { await model.togglePlayPause() }
        } label: {
            Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 38))
                .frame(width: 72, height: 72)
                .background(contentColor.opacity(0.18), in: Circle())
                .overlay(Circle().strokeBorder(contentColor.opacity(0.6), lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
    }

    private func transport(_ symbol: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Options

    private var optionsSection: some View {
        HStack(spacing: 12) {
            optionButton(repeatSymbol, active: repeatActive) { await model.cycleRepeat() }
            optionButton("shuffle", active: model.properties?.shuffled ?? false) { await model.toggleShuffle() }
            audioMenu
            subtitleMenu
            optionButton("aspectratio") { await model.cycleAspect() }
        }
        .foregroundStyle(contentColor)
    }

    private var repeatSymbol: String {
        (model.properties?.repeatMode ?? "off") == "one" ? "repeat.1" : "repeat"
    }

    private var repeatActive: Bool {
        (model.properties?.repeatMode ?? "off") != "off"
    }

    private var audioMenu: some View {
        Menu {
            let streams = model.properties?.audiostreams ?? []
            if streams.isEmpty {
                Text("No audio streams")
            } else {
                ForEach(streams, id: \.index) { stream in
                    Button {
                        Task { await model.selectAudioStream(index: stream.index) }
                    } label: {
                        if stream.index == model.properties?.currentaudiostream?.index {
                            Label(audioLabel(stream), systemImage: "checkmark")
                        } else {
                            Text(audioLabel(stream))
                        }
                    }
                }
            }
        } label: {
            optionIcon("waveform")
        }
        .accessibilityLabel("Audio stream")
    }

    private var subtitleMenu: some View {
        Menu {
            Button {
                Task { await model.subtitlesOff() }
            } label: {
                if subtitlesOff {
                    Label("Off", systemImage: "checkmark")
                } else {
                    Text("Off")
                }
            }
            ForEach(model.properties?.subtitles ?? [], id: \.index) { stream in
                Button {
                    Task { await model.selectSubtitle(index: stream.index) }
                } label: {
                    if stream.index == model.properties?.currentsubtitle?.index, !subtitlesOff {
                        Label(subtitleLabel(stream), systemImage: "checkmark")
                    } else {
                        Text(subtitleLabel(stream))
                    }
                }
            }
        } label: {
            optionIcon("captions.bubble")
        }
        .accessibilityLabel("Subtitles")
    }

    private var subtitlesOff: Bool {
        guard let stream = model.properties?.currentsubtitle else { return true }
        return stream.name.isEmpty && stream.language.isEmpty
    }

    private func audioLabel(_ stream: AudioStream) -> String {
        if !stream.name.isEmpty { return stream.name }
        if !stream.language.isEmpty { return stream.language }
        return "Stream \(stream.index)"
    }

    private func subtitleLabel(_ stream: SubtitleStream) -> String {
        if !stream.name.isEmpty { return stream.name }
        if !stream.language.isEmpty { return stream.language }
        return "Stream \(stream.index)"
    }

    private func optionButton(_ symbol: String, active: Bool = false, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            optionIcon(symbol, active: active)
        }
        .buttonStyle(.plain)
    }

    private func optionIcon(_ symbol: String, active: Bool = false) -> some View {
        Image(systemName: symbol)
            .font(.title3)
            .frame(width: 44, height: 44)
            .background(active ? AnyShapeStyle(contentColor.opacity(0.25)) : AnyShapeStyle(Color.clear),
                        in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
    }

    // MARK: Titles

    private var title: String {
        if let item = model.item, !item.title.isEmpty { return item.title }
        if let item = model.item, !item.label.isEmpty { return item.label }
        return "Nothing playing"
    }

    private var subtitle: String { model.item?.subtitleLine ?? "" }
}

/// The current item's details, shown from the overlay without leaving it.
struct NowPlayingInfoView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 14) {
                        ArtworkImage(
                            url: Artwork.poster(for: model.item?.art ?? [:], thumbnail: model.item?.thumbnail ?? ""),
                            username: model.host.username,
                            password: model.password,
                            size: 96
                        )
                        VStack(alignment: .leading, spacing: 6) {
                            Text(infoTitle)
                                .font(.title3.bold())
                            if let line = model.item?.infoLine, !line.isEmpty {
                                Text(line)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }

                    if let plot = model.item?.plot, !plot.isEmpty {
                        Text(plot)
                            .font(.body)
                    } else {
                        Text("No description available.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
            .themedScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var infoTitle: String {
        if let item = model.item, !item.title.isEmpty { return item.title }
        if let item = model.item, !item.label.isEmpty { return item.label }
        return "Nothing playing"
    }
}

/// Render a duration as `m:ss`, or `h:mm:ss` once it passes an hour. Pure so it
/// is unit-testable without a running player.
enum TimeText {
    static func mmss(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
