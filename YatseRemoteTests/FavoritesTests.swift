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

    /// A favourite saved from the player lines up under the host's own item type,
    /// and an unrecognised one says "Media" rather than leaving the line blank.
    func testFavouriteDetailLineNamesThePlayingKind() {
        XCTAssertEqual(FavoritesScreen.detailLine(for: .media(file: "/x.mkv", kind: "movie")), "Movie")
        XCTAssertEqual(FavoritesScreen.detailLine(for: .media(file: "/x.mkv", kind: "episode")), "Episode")
        XCTAssertEqual(FavoritesScreen.detailLine(for: .media(file: "/x.mp3", kind: "song")), "Song")
        XCTAssertEqual(FavoritesScreen.detailLine(for: .media(file: "/x.ts", kind: "channel")), "Media")
    }

    // MARK: Saving what is playing

    /// The live shape the box reported for the item playing when this was measured —
    /// `KodiModelTests.livePlayerItem`, trimmed. Note what is here: `type`, `file`,
    /// `title`, `label`, `art`. And what is not: any library id, which is why the
    /// file is the key.
    private static let playingMovie = #"""
    {"album":"", "art":{"poster":"image://http%3a%2f%2fbox%3a8096%2fItems%2fx%2fImages%2fPrimary%2f0/"}, "artist":[], "episode":-1, "fanart":"", "file":"http://10.13.13.2:8096/Videos/5c6b025c8497c194381a5a02306b05c9/stream?static=True&PlaySessionId=0ecbe6d7ac8b48e389be583a14bd670e", "label":"CL", "runtime":1810, "season":-1, "showtitle":"", "thumbnail":"image://x.png/", "title":"CL", "type":"movie"}
    """#

    private func playing(_ json: String) throws -> PlayerItem {
        try JSONDecoder().decode(PlayerItem.self, from: Data(json.utf8))
    }

    func testAFavouriteSavedFromThePlayerReplaysThatFile() throws {
        let item = try playing(Self.playingMovie)
        let favorite = try XCTUnwrap(Favorite(playing: item))

        XCTAssertEqual(favorite.title, "CL")
        XCTAssertEqual(favorite.target, .media(file: item.file, kind: "movie"))
        XCTAssertEqual(favorite.target.playableItem?["file"] as? String, item.file)

        let store = FavoriteStore()
        store.toggle(favorite)
        XCTAssertTrue(store.contains(favorite.target))
        XCTAssertEqual(store.items.count, 1)
    }

    /// Identity is the file, not the kind: the same item saved again — with whatever
    /// type or title the host reports this time — replaces rather than duplicating.
    func testAMediaFavouriteIsKeyedOnItsFileNotItsKind() {
        let file = "smb://box/films/film.mkv"
        let store = FavoriteStore()
        store.toggle(Favorite(title: "Film", target: .media(file: file, kind: "movie")))
        store.toggle(Favorite(title: "Film (2)", target: .media(file: file, kind: "episode")))
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.title, "Film (2)")
    }

    /// The star's favourite is read back by a later launch, payload included — the
    /// store decodes with `try?`, so a case that did not round-trip would vanish
    /// without a word.
    func testAMediaFavouriteSurvivesAReload() throws {
        let item = try playing(Self.playingMovie)
        let favorite = try XCTUnwrap(Favorite(playing: item))
        FavoriteStore().toggle(favorite)

        let reloaded = FavoriteStore()
        XCTAssertTrue(reloaded.contains(favorite.target))
        XCTAssertEqual(reloaded.items.first?.target.playableItem?["file"] as? String, item.file)
    }

    /// Nothing to replay, or nothing to name it with, means no star — the overlay
    /// draws it from this, so it is absent rather than dead.
    func testAPlayingItemWithNothingToSaveHasNoFavourite() throws {
        let noFile = try playing(#"{"title":"Live stream","type":"unknown","file":""}"#)
        XCTAssertNil(Favorite(playing: noFile))

        let noName = try playing(#"{"title":"","label":"","file":"smb://box/film.mkv","type":"movie"}"#)
        XCTAssertNil(Favorite(playing: noName))
    }

    /// The name follows the overlay's own rule: the title, falling back to the label.
    func testASavedItemTakesTheOverlaysNameForIt() throws {
        let item = try playing(#"{"title":"","label":"CL","file":"smb://box/film.mkv","type":"movie"}"#)
        XCTAssertEqual(Favorite(playing: item)?.title, "CL")
    }

    /// Only an item is playable. A place is navigated to, and an item with no file
    /// has no payload to send.
    func testOnlyAMediaFavouriteHasAPlayableItem() {
        XCTAssertNil(FavoriteTarget.section("movies").playableItem)
        XCTAssertNil(FavoriteTarget.directory(path: "/media").playableItem)
        XCTAssertNil(FavoriteTarget.episodes(tvshowID: 1).playableItem)
        XCTAssertNil(FavoriteTarget.media(file: "", kind: "movie").playableItem)
    }
}
