import SwiftUI

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
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.divider)
                .frame(height: 1.5)
        }
    }

    private var title: String {
        let item = model.item
        if let item, !item.title.isEmpty { return item.title }
        if let item, !item.label.isEmpty { return item.label }
        return "Nothing playing"
    }

    private var subtitle: String { model.item?.subtitleLine ?? "" }

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
