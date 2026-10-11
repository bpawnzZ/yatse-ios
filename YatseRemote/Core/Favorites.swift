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

    var id: String { target.id }
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
