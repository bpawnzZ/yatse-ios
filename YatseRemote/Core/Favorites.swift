import Foundation

/// A place in the app worth returning to: a library, a show's episodes, an
/// artist's albums, or a folder on the media centre. One type covers every
/// destination the navigation can reach, so the drawer, the star buttons and
/// the store all speak the same language.
enum FavoriteTarget: Codable, Hashable {
    case section(String)
    case episodes(tvshowID: Int)
    case albumsOfArtist(artistID: Int)
    case directory(path: String)

    /// Stable identity for a target. Saving the same place twice must replace
    /// rather than append, and the star buttons decide filled-vs-outline from
    /// this, so it may not depend on anything time- or session-dependent.
    var id: String {
        switch self {
        case .section(let raw): return "section:\(raw)"
        case .episodes(let id): return "episodes:\(id)"
        case .albumsOfArtist(let id): return "albums:\(id)"
        case .directory(let path): return "directory:\(path)"
        }
    }
}

/// One saved favourite.
struct Favorite: Codable, Hashable, Identifiable {
    var title: String
    var target: FavoriteTarget
    /// Artwork of the place it was saved from, so the Favorites grid can show a
    /// poster rather than a list of names.
    ///
    /// Both of these MUST stay optional. `FavoriteStore.load()` decodes with
    /// `try?`, so making either one non-optional would make every favourite saved
    /// by an earlier build fail to decode and vanish without a word — the trap
    /// `Host.lastCheck` already documents.
    var art: [String: String]? = nil
    var thumbnail: String? = nil

    var id: String { target.id }
}

extension Favorite {
    /// Saving an add-on saves the plugin root it browses from.
    init(addon: Addon) {
        self.init(title: addon.displayName,
                  target: .directory(path: addon.browsePath),
                  thumbnail: addon.thumbnail)
    }

    /// Saving an entry inside an add-on saves the place that entry opens.
    init(directoryEntry item: MediaItem) {
        self.init(title: item.heading,
                  target: .directory(path: item.file),
                  art: item.art,
                  thumbnail: item.thumbnail)
    }

    /// The poster for this favourite, resolved against the host it belongs to —
    /// add-on artwork needs the host's image endpoint, see `Artwork.url(_:host:)`.
    func artworkURL(host: Host) -> URL? {
        Artwork.poster(for: art ?? [:], thumbnail: thumbnail ?? "", host: host)
    }
}

/// The saved favourites, persisted. Same shape as `HostStore`: a small
/// `ObservableObject` over `UserDefaults`, so there is one persistence pattern
/// in the app rather than two.
final class FavoriteStore: ObservableObject {
    @Published private(set) var items: [Favorite] = []

    private let defaultsKey = "yatse.favorites.v1"

    init() { load() }

    func contains(_ target: FavoriteTarget) -> Bool {
        items.contains { $0.id == target.id }
    }

    /// Adds the favourite, or replaces the existing entry for the same place —
    /// the title can change (a renamed folder) even when the target does not.
    func toggle(_ favorite: Favorite) {
        if let index = items.firstIndex(where: { $0.id == favorite.id }) {
            items[index] = favorite
        } else {
            items.append(favorite)
        }
        save()
    }

    func remove(_ favorite: Favorite) {
        items.removeAll { $0.id == favorite.id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return }
        // A stored list that no longer decodes is dropped rather than crashing:
        // favourites are a convenience, and losing them is better than refusing
        // to launch.
        items = (try? JSONDecoder().decode([Favorite].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
