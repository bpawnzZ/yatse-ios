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
}
