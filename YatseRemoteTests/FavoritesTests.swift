import XCTest
@testable import YatseRemote

/// The favourites store: identity, de-duplication and the round trip through
/// `UserDefaults`.
///
/// The storage key is asserted literally, so renaming it — which would silently
/// orphan every saved favourite on the next launch — fails here instead of on
/// someone's device.
final class FavoritesTests: XCTestCase {
    private let key = "yatse.favorites.v1"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    // MARK: Identity

    func testSamePlaceHasTheSameIdentity() {
        XCTAssertEqual(FavoriteTarget.section("movies").id, FavoriteTarget.section("movies").id)
        XCTAssertNotEqual(FavoriteTarget.section("movies").id, FavoriteTarget.section("tvshows").id)
    }

    /// Two different kinds of target must not collide on the same number: id 7
    /// as a show and id 7 as an artist are different places.
    func testTargetsOfDifferentKindsDoNotShareIdentity() {
        XCTAssertNotEqual(FavoriteTarget.episodes(tvshowID: 7).id,
                          FavoriteTarget.albumsOfArtist(artistID: 7).id)
        XCTAssertNotEqual(FavoriteTarget.directory(path: "7").id,
                          FavoriteTarget.episodes(tvshowID: 7).id)
    }

    // MARK: Adding

    func testSavingTheSamePlaceTwiceReplacesRatherThanAppends() {
        let store = FavoriteStore()
        store.toggle(Favorite(title: "Movies", target: .section("movies")))
        store.toggle(Favorite(title: "Films", target: .section("movies")))
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.title, "Films")
    }

    func testContainsMatchesByTargetNotByTitle() {
        let store = FavoriteStore()
        store.toggle(Favorite(title: "Anything", target: .section("movies")))
        XCTAssertTrue(store.contains(.section("movies")))
        XCTAssertFalse(store.contains(.section("tvshows")))
    }

    func testRemovingOneLeavesTheRest() {
        let store = FavoriteStore()
        store.toggle(Favorite(title: "A", target: .section("movies")))
        store.toggle(Favorite(title: "B", target: .section("tvshows")))
        store.remove(Favorite(title: "A", target: .section("movies")))
        XCTAssertEqual(store.items.map(\.title), ["B"])
    }

    // MARK: Persistence

    func testFavouritesSurviveAReload() {
        let store = FavoriteStore()
        store.toggle(Favorite(title: "Episodes", target: .episodes(tvshowID: 42)))
        store.toggle(Favorite(title: "Films", target: .directory(path: "/media/films")))

        let reloaded = FavoriteStore()
        XCTAssertEqual(reloaded.items.map(\.title), ["Episodes", "Films"])
        XCTAssertTrue(reloaded.contains(.episodes(tvshowID: 42)))
        XCTAssertTrue(reloaded.contains(.directory(path: "/media/films")))
    }

    func testRemovalIsPersisted() {
        FavoriteStore().toggle(Favorite(title: "A", target: .section("movies")))
        let store = FavoriteStore()
        store.remove(Favorite(title: "A", target: .section("movies")))
        XCTAssertTrue(FavoriteStore().items.isEmpty)
    }

    /// Favourites are a convenience: a stored list that no longer decodes is
    /// dropped rather than taking the launch down with it.
    func testCorruptStoredDataIsDroppedRatherThanCrashing() {
        UserDefaults.standard.set(Data("not json".utf8), forKey: key)
        XCTAssertTrue(FavoriteStore().items.isEmpty)
    }

    // MARK: Artwork

    /// The artwork fields are optional so that a favourite stored by an earlier
    /// build — whose JSON has no artwork keys at all — still decodes. Making
    /// either non-optional would silently drop every favourite already saved,
    /// because `load()` decodes with `try?`.
    func testFavouriteStoredWithoutArtworkKeysStillDecodes() throws {
        let stored = Favorite(title: "Movies", target: .section("movies"))
        let data = try JSONEncoder().encode(stored)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("\"art\""), "a nil artwork must not be written: \(json)")

        let decoded = try JSONDecoder().decode(Favorite.self, from: data)
        XCTAssertEqual(decoded, stored)
        XCTAssertNil(decoded.art)
        XCTAssertNil(decoded.thumbnail)
    }

    func testArtworkSurvivesTheRoundTrip() throws {
        let saved = Favorite(title: "My Subscriptions",
                             target: .directory(path: "plugin://plugin.video.youtube/special/my_subscriptions"),
                             art: ["thumb": "image://special%3a%2f%2fhome%2faddons%2fx.png"],
                             thumbnail: "")
        let decoded = try JSONDecoder().decode(Favorite.self, from: try JSONEncoder().encode(saved))
        XCTAssertEqual(decoded.art?["thumb"], "image://special%3a%2f%2fhome%2faddons%2fx.png")
    }

    /// A favourite saved before artwork was recorded still resolves a URL — the
    /// host's image endpoint — so its tile renders the placeholder rather than
    /// failing.
    func testFavouriteArtworkIsResolvedForItsHost() throws {
        var host = Host()
        host.address = "10.13.13.7"
        host.port = 8080

        let withArt = Favorite(title: "Subscriptions",
                               target: .directory(path: "plugin://plugin.video.youtube/special/x"),
                               thumbnail: "image://%2fstorage%2ficon.png")
        XCTAssertEqual(withArt.artworkURL(host: host)?.absoluteString,
                       "http://10.13.13.7:8080/image/%2fstorage%2ficon.png")

        XCTAssertNil(Favorite(title: "Bare", target: .directory(path: "/media/films")).artworkURL(host: host))
    }

    // MARK: Saving from the browse

    /// Saving an add-on saves the plugin root, and saving an entry inside one
    /// saves the place that entry opens — two different places, so two favourites.
    func testSavingAnAddonAndAnEntrySaveDifferentPlaces() throws {
        let addon = Addon(addonid: "plugin.video.youtube", type: "xbmc.python.pluginsource",
                          name: "YouTube", thumbnail: "image://%2ficon.png")
        let root = Favorite(addon: addon)
        XCTAssertEqual(root.title, "YouTube")
        XCTAssertEqual(root.target, .directory(path: "plugin://plugin.video.youtube/"))
        XCTAssertEqual(root.thumbnail, "image://%2ficon.png")

        let entry = try JSONDecoder().decode(MediaItem.self, from: Data(#"""
        {"label":"[B]My Subscriptions[/B]","file":"plugin://plugin.video.youtube/special/my_subscriptions","filetype":"directory"}
        """#.utf8))
        let child = Favorite(directoryEntry: entry)
        // The saved title is the displayed one, with Kodi's markup already gone.
        XCTAssertEqual(child.title, "My Subscriptions")
        XCTAssertEqual(child.target, .directory(path: "plugin://plugin.video.youtube/special/my_subscriptions"))
        XCTAssertNotEqual(root.id, child.id)
    }

    func testSavingTheSameEntryTwiceKeepsOneWithTheNewerArtwork() {
        let store = FavoriteStore()
        let path = "plugin://plugin.video.youtube/special/x"
        store.toggle(Favorite(title: "Old", target: .directory(path: path)))
        store.toggle(Favorite(title: "New", target: .directory(path: path),
                              art: ["thumb": "image://y.png"]))
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.title, "New")
        XCTAssertEqual(store.items.first?.art?["thumb"], "image://y.png")
    }

    /// The Favorites grid's second line names what the favourite points at.
    func testFavouriteDetailLineNamesThePlace() {
        XCTAssertEqual(FavoritesScreen.detailLine(for: .section("movies")), "Movies")
        XCTAssertEqual(FavoritesScreen.detailLine(for: .episodes(tvshowID: 1)), "Episodes")
        XCTAssertEqual(FavoritesScreen.detailLine(for: .directory(path: "plugin://p.v/")), "Add-on")
        XCTAssertEqual(FavoritesScreen.detailLine(for: .directory(path: "/media/films")), "Folder")
    }
}
