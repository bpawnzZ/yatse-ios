import SwiftUI

/// The pull gesture on the playback tray: up on the bar opens the full player,
/// down on that player closes it again. Pure so the threshold and the axis rule
/// are testable without a running host.
enum TraySwipe {
    /// Travel before a drag counts as a pull rather than a tap or a wobble.
    static let minimumTravel: CGFloat = 48

    enum Direction { case up, down }

    /// True when the drag is mostly vertical, long enough, and heading `direction`.
    ///
    /// The axis rule is the point: without it a sideways move across the bar — a
    /// thumb sliding toward the transport buttons — would open a full-screen
    /// surface, and the bar carries buttons that are dragged over all the time.
    static func isPull(_ translation: CGSize, direction: Direction) -> Bool {
        let dy = translation.height
        guard abs(dy) >= minimumTravel, abs(dy) > abs(translation.width) else { return false }
        return direction == .up ? dy < 0 : dy > 0
    }
}

/// The playback bar pinned above every destination while a player is active, so
/// playback is always visible and one tap from the Remote.
struct MiniPlayer: View {
    @ObservedObject var model: AppModel
    let onOpen: () -> Void

    @Environment(\.remoteTheme) private var theme

    /// Shown only while a player is active. Kept static and pure so the rule is
    /// unit-testable without a running host — the model is responsible for
    /// clearing `activePlayer` when playback ends, so the bar cannot outlive it.
    static func isVisible(activePlayer: ActivePlayer?) -> Bool {
        activePlayer != nil
    }

    /// Whether the bar can show progress at all. A duration is what makes both
    /// readouts mean something: a live stream reports none, and "0:00 of 0:00"
    /// over an empty line is worse than saying nothing. The top edge falls back
    /// to the plain divider when this is false. Pure, so it is testable without a
    /// running host.
    static func showsProgress(durationSeconds: Double) -> Bool {
        durationSeconds > 0
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                ArtworkImage(
                    url: Artwork.poster(for: model.item?.art ?? [:], thumbnail: model.item?.thumbnail ?? ""),
                    username: model.host.username,
                    password: model.password,
                    size: 40
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(theme.icon.opacity(0.75))
                            .lineLimit(1)
                    }
                    if MiniPlayer.showsProgress(durationSeconds: model.durationSeconds) {
                        // The full player's own wording, monospaced so a 1 Hz
                        // refresh cannot make the line jitter.
                        Text("\(TimeText.mmss(model.positionSeconds)) of \(TimeText.mmss(model.durationSeconds))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(theme.icon.opacity(0.75))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)

            control("stop", label: "Stop") { await model.stopPlayback() }
            control(model.isPlaying ? "pause" : "play", label: model.isPlaying ? "Pause" : "Play") {
                await model.togglePlayPause()
            }
            control("forward.end", label: "Next") { await model.skip("next") }
        }
        .foregroundStyle(theme.icon)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.barFill)
        .overlay(alignment: .top) { topEdge }
        // Pull the bar up to open the full player. `minimumDistance` is the same
        // threshold the rule uses, so a tap still reaches stop/pause/next: a tap
        // never travels far enough to be recognised as a drag at all.
        .gesture(
            DragGesture(minimumDistance: TraySwipe.minimumTravel)
                .onEnded { value in
                    if TraySwipe.isPull(value.translation, direction: .up) { onOpen() }
                }
        )
    }

    private var title: String {
        let item = model.item
        if let item, !item.title.isEmpty { return item.title }
        if let item, !item.label.isEmpty { return item.label }
        return "Nothing playing"
    }

    private var subtitle: String { model.item?.subtitleLine ?? "" }

    /// The bar's top edge: how much of the item has played, in place of the plain
    /// divider, whenever there is a duration to show.
    ///
    /// Drawn here rather than reusing `SeekTrack` — that one is a scrubber, and a
    /// thumb on the dock would sit under the pull-to-open gesture and invite a
    /// drag it cannot honour. The computation is still shared: `SeekFraction`
    /// decides the share and `TimeText` renders the times, exactly as the full
    /// player does.
    @ViewBuilder
    private var topEdge: some View {
        if MiniPlayer.showsProgress(durationSeconds: model.durationSeconds) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(theme.divider)
                    Rectangle()
                        .fill(theme.accent)
                        .frame(width: geo.size.width * SeekFraction.of(
                            position: model.positionSeconds,
                            duration: model.durationSeconds
                        ))
                }
            }
            .frame(height: 2.5)
        } else {
            Rectangle()
                .fill(theme.divider)
                .frame(height: 1.5)
        }
    }

    /// Outlined transport icons throughout — the filled variants read as heavy
    /// against a translucent bar.
    private func control(_ symbol: String, label: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
