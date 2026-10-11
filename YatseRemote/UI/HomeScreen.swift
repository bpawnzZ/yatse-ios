import SwiftUI

/// A minimal home dashboard: tiles that jump to the main destinations, and the
/// now-playing line. The library redesign is a later phase.
struct HomeScreen: View {
    @ObservedObject var model: AppModel
    let onOpenDrawer: () -> Void
    let onSelect: (ShellDestination) -> Void

    private let tiles: [ShellDestination] = [.movies, .tvShows, .music, .remote, .settings, .about]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                nowPlaying

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(tiles) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Image(systemName: item.systemImage)
                                    .font(.title2)
                                    .foregroundStyle(.tint)
                                Text(item.title)
                                    .font(.headline)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Home")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { onOpenDrawer() } label: { Image(systemName: "line.3.horizontal") }
                    .accessibilityLabel("Open menu")
            }
        }
    }

    private var nowPlaying: some View {
        HStack(spacing: 12) {
            ArtworkImage(
                url: Artwork.poster(for: model.item?.art ?? [:], thumbnail: model.item?.thumbnail ?? ""),
                username: model.host.username,
                password: model.password,
                size: 56
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(model.item?.title.isEmpty == false ? (model.item?.title ?? "") : (model.item?.label ?? "Nothing playing"))
                    .font(.headline)
                    .lineLimit(1)
                Text(model.item?.subtitleLine.isEmpty == false ? (model.item?.subtitleLine ?? "") : "Idle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
    }
}
