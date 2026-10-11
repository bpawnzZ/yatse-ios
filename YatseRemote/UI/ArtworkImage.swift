import SwiftUI
import UIKit

/// Kodi's webserver protects `/image/...` with the same Basic auth as JSON-RPC,
/// so `AsyncImage` gets a 401 — the artwork has to be fetched with credentials.
struct ArtworkImage: View {
    let url: URL?
    let username: String
    let password: String
    var size: CGFloat = 56

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.quaternary)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else {
            image = nil
            return
        }
        if let cached = ArtworkCache.shared.image(for: url) {
            image = cached
            return
        }

        var request = URLRequest(url: url)
        if !username.isEmpty || !password.isEmpty {
            let token = Data("\(username):\(password)".utf8).base64EncodedString()
            request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let loaded = UIImage(data: data) else { return }

        ArtworkCache.shared.store(loaded, for: url)
        image = loaded
    }
}

final class ArtworkCache {
    static let shared = ArtworkCache()

    private let cache = NSCache<NSURL, UIImage>()

    private init() { cache.countLimit = 300 }

    func image(for url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    func store(_ image: UIImage, for url: URL) { cache.setObject(image, forKey: url as NSURL) }
}

/// One row shape for every library list.
struct MediaRow: View {
    let item: MediaItem
    let username: String
    let password: String
    var showsChevron = false

    var body: some View {
        HStack(spacing: 12) {
            ArtworkImage(
                url: Artwork.poster(for: item.art, thumbnail: item.thumbnail),
                username: username,
                password: password
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.heading)
                    .font(.body)
                    .lineLimit(2)
                if !item.detailLine.isEmpty {
                    Text(item.detailLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
