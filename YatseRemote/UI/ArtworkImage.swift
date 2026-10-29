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

        guard let (data, response) = try? await ArtworkSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let image = UIImage(data: data) else { return nil }

        ArtworkCache.shared.store(image, for: url)
        return image
    }
}

/// The session every artwork fetch goes through, because add-on artwork is the
/// one place this app talks to a server the *user* configured rather than the
/// host it already trusts.
///
/// Concretely: JellyCon hands back `https://10.13.13.2:54406/Items/…` and that
/// server's certificate is issued by a home-lab CA (`LUCABRASI Local CA`) which
/// no device has been told to trust, so `URLSession` refuses the handshake and
/// the tile falls back to a placeholder — with no error anywhere. Everything
/// else worked: PKC's artwork is `plex.direct` (a certificate the device already
/// accepts) and library artwork is plain `http`.
///
/// So the exception is scoped to where it can apply: a **private or loopback
/// address**, or a `.local` name, is accepted; a public hostname still has to
/// validate normally, which is why `plex.direct`/`ytimg`/TMDB keep their real
/// chain. This is a deliberate, documented downgrade for LAN servers with
/// self-signed certificates — the alternative is asking the user to install the
/// CA profile on the device, which fixes one CA and not the next add-on's.
final class ArtworkSession: NSObject, URLSessionDelegate {
    static let shared: URLSession = URLSession(
        configuration: .default,
        delegate: ArtworkSession(),
        delegateQueue: nil
    )

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              Self.isLocal(challenge.protectionSpace.host) else {
            return completionHandler(.performDefaultHandling, nil)
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    /// The scope of the exception above — pure so it can be tested without a host.
    static func isLocal(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".local") { return true }
        // A public hostname has no numeric octets, so it never gets here.
        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }
        switch (octets[0], octets[1]) {
        case (10, _), (127, _): return true         // 10/8, loopback
        case (192, 168): return true                // 192.168/16
        case (172, 16...31): return true            // 172.16/12
        default: return false
        }
    }
}

/// Full-bleed artwork behind a surface while something is playing. The scrim is
/// the theme's own tint, so blue stays blue instead of blacking the artwork out.
///
/// The blur is the caller's: the Remote keeps the theme's radius because
/// `app-shell` requires its backdrop blurred while something plays, and the Now
/// Playing overlay passes 0 because its own requirement is a sharp artwork.
struct ArtworkBackground: View {
    let url: URL?
    let username: String
    let password: String
    /// No default, so a new call site has to choose which of the two it wants.
    let blur: CGFloat

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
            .blur(radius: blur)
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

/// The list-mode row for a saved favourite: the shape `MediaRow` gives a library
/// item, built from what a favourite records rather than from a `MediaItem`.
struct FavoriteRow: View {
    let favorite: Favorite
    let artURL: URL?
    let username: String
    let password: String
    /// What the row's second line says. Defaults to the kind of place the
    /// favourite names; a caller with better information — an add-on's version
    /// and state, say — passes it instead.
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            ArtworkImage(url: artURL, username: username, password: password)

            VStack(alignment: .leading, spacing: 2) {
                Text(favorite.title)
                    .font(.body)
                    .lineLimit(2)
                Text(detail ?? FavoritesScreen.detailLine(for: favorite.target))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }
}
