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
        image = await ArtworkLoader.load(url, username: username, password: password)
    }
}

/// Shared authenticated artwork fetch, used by the row image and the remote's
/// blurred background so both ride the same cache and the same Basic-auth path.
enum ArtworkLoader {
    static func load(_ url: URL, username: String, password: String) async -> UIImage? {
        if let cached = ArtworkCache.shared.image(for: url) { return cached }

        var request = URLRequest(url: url)
        if !username.isEmpty || !password.isEmpty {
            let token = Data("\(username):\(password)".utf8).base64EncodedString()
            request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let image = UIImage(data: data) else { return nil }

        ArtworkCache.shared.store(image, for: url)
        return image
    }
}

/// Full-bleed blurred artwork behind the remote while something is playing. The
/// scrim is the theme's own tint, so blue stays blue instead of blacking the
/// artwork out.
struct ArtworkBackground: View {
    let url: URL?
    let username: String
    let password: String

    @Environment(\.remoteTheme) private var theme
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color.clear
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .blur(radius: 30)
            .overlay(theme.artworkScrim)
            .ignoresSafeArea()
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            image = await ArtworkLoader.load(url, username: username, password: password)
        }
    }
}

final class ArtworkCache {
    static let shared = ArtworkCache()

    private let cache = NSCache<NSURL, UIImage>()

    private init() { cache.countLimit = 300 }

    func image(for url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    func store(_ image: UIImage, for url: URL) { cache.setObject(image, forKey: url as NSURL) }
}

/// A container-filling artwork image with a 2:3 poster aspect, for grid tiles.
/// Separate from `ArtworkImage`, whose fixed square contract the rows rely on.
struct PosterImage: View {
    let url: URL?
    let username: String
    let password: String

    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else {
            image = nil
            return
        }
        image = await ArtworkLoader.load(url, username: username, password: password)
    }
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
