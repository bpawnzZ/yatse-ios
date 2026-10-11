import SwiftUI

/// The playback bar pinned above every destination while a player is active, so
/// playback is always visible and one tap from the Remote.
struct MiniPlayer: View {
    @ObservedObject var model: AppModel
    let onOpen: () -> Void

    /// Shown only while a player is active. Kept static and pure so the rule is
    /// unit-testable without a running host.
    static func isVisible(activePlayer: ActivePlayer?) -> Bool {
        activePlayer != nil
    }

    var body: some View {
        HStack(spacing: 12) {
            ArtworkImage(
                url: Artwork.poster(for: model.item?.art ?? [:], thumbnail: model.item?.thumbnail ?? ""),
                username: model.host.username,
                password: model.password,
                size: 40
            )

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)

            control("stop.fill") { await model.stopPlayback() }
            control(model.isPlaying ? "pause.fill" : "play.fill") { await model.togglePlayPause() }
            control("forward.fill") { await model.skip("next") }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var title: String {
        let item = model.item
        if let item, !item.title.isEmpty { return item.title }
        if let item, !item.label.isEmpty { return item.label }
        return "Nothing playing"
    }

    private var subtitle: String { model.item?.subtitleLine ?? "" }

    private func control(_ symbol: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
