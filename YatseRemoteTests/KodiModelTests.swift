import XCTest
@testable import YatseRemote

/// Fixtures are verbatim responses captured from a live Kodi 21.3-Omega box
/// (LibreELEC, JSON-RPC v13) rather than hand-written JSON — see the
/// `System.FriendlyName` case below for a shape only the real server produced.
final class KodiModelTests: XCTestCase {

    // MARK: Fixtures

    private static let livePlayerProperties = #"""
    {"id": 2, "jsonrpc": "2.0", "result": {"audiostreams": [{"bitrate": 127089, "channels": 2, "codec": "aac", "index": 0, "isdefault": true, "isimpaired": false, "isoriginal": false, "language": "swe", "name": "AAC-LC stereo", "samplerate": 0}], "currentaudiostream": {"bitrate": 127089, "channels": 2, "codec": "aac", "index": 0, "isdefault": true, "isimpaired": false, "isoriginal": false, "language": "swe", "name": "AAC-LC stereo", "samplerate": 0}, "currentsubtitle": {}, "partymode": false, "percentage": 86.01700592041016, "playlistid": 1, "position": 0, "repeat": "off", "shuffled": false, "speed": 1, "subtitles": [], "time": {"hours": 0, "milliseconds": 931, "minutes": 25, "seconds": 56}, "totaltime": {"hours": 0, "milliseconds": 27, "minutes": 30, "seconds": 10}}}
    """#

    private static let livePlayerItem = #"""
    {"id": 3, "jsonrpc": "2.0", "result": {"item": {"album": "", "art": {"icon": "image://DefaultFolder.png/", "poster": "image://http%3a%2f%2f10.13.13.2%3a8096%2fItems%2f5c6b025c8497c194381a5a02306b05c9%2fImages%2fPrimary%2f0%3fFormat%3doriginal%26Tag%3d024aca21364b0c66e78cd671a17f24a0/", "thumb": "image://http%3a%2f%2f10.13.13.2%3a8096%2fItems%2f5c6b025c8497c194381a5a02306b05c9%2fImages%2fPrimary%2f0%3fFormat%3doriginal%26Tag%3d024aca21364b0c66e78cd671a17f24a0/"}, "artist": [], "episode": -1, "fanart": "", "file": "http://10.13.13.2:8096/Videos/5c6b025c8497c194381a5a02306b05c9/stream?static=True&PlaySessionId=0ecbe6d7ac8b48e389be583a14bd670e&MediaSourceId=5c6b025c8497c194381a5a02306b05c9", "label": "CL", "runtime": 1810, "season": -1, "showtitle": "", "thumbnail": "image://http%3a%2f%2f10.13.13.2%3a8096%2fItems%2f5c6b025c8497c194381a5a02306b05c9%2fImages%2fPrimary%2f0%3fFormat%3doriginal%26Tag%3d024aca21364b0c66e78cd671a17f24a0/", "title": "CL", "type": "movie"}}}
    """#

    private static let liveApplication = #"""
    {"id": 1, "jsonrpc": "2.0", "result": {"muted": false, "name": "Kodi", "version": {"major": 21, "minor": 3, "revision": "21.3-Omega", "tag": "stable"}, "volume": 50}}
    """#

    private static let liveMovies = #"""
    {"id": 4, "jsonrpc": "2.0", "result": {"limits": {"end": 1, "start": 0, "total": 4320}, "movies": [{"art": {"fanart": "image://https%3a%2f%2f10-0-0-129.ea9fa151a2af4395aca7d4191dedd86d.plex.direct%3a32400%2fphoto%2f%3a%2ftranscode%3fwidth%3d1920%26height%3d1920%26minSize%3d1%26upscale%3d0%26url%3d%2flibrary%2fmetadata%2f9523%2fart%2f1788642607%26X-Plex-Token%3dYJ4pRp-aeTDPC_1a7-jY/", "icon": "image://DefaultVideo.png/", "poster": "image://https%3a%2f%2f10-0-0-129.ea9fa151a2af4395aca7d4191dedd86d.plex.direct%3a32400%2fphoto%2f%3a%2ftranscode%3fwidth%3d1920%26height%3d1920%26minSize%3d1%26upscale%3d0%26url%3d%2flibrary%2fmetadata%2f9523%2fthumb%2f1788642607%26X-Plex-Token%3dYJ4pRp-aeTDPC_1a7-jY/"}, "label": "", "movieid": 1998, "playcount": 8, "runtime": 165, "thumbnail": "", "title": "", "year": 2026}]}}
    """#

    private static let methodNotFound = #"""
    {"error": {"code": -32601, "message": "Method not found."}, "id": 5, "jsonrpc": "2.0"}
    """#

    private func result<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        let envelope = try JSONDecoder().decode(RPCEnvelope<T>.self, from: Data(json.utf8))
        return try XCTUnwrap(envelope.result)
    }

    // MARK: Live payload decoding

    func testPlayerPropertiesFromLiveKodi() throws {
        let properties = try result(PlayerProperties.self, from: Self.livePlayerProperties)

        XCTAssertEqual(properties.speed, 1)
        XCTAssertTrue(properties.isPlaying)
        XCTAssertEqual(properties.playlistid, 1)
        XCTAssertEqual(properties.repeatMode, "off")
        XCTAssertFalse(properties.shuffled)
        XCTAssertEqual(properties.percentage, 86.01700592041016, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(properties.time).totalSeconds, 1556.931, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(properties.totaltime).totalSeconds, 1810.027, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(properties.currentaudiostream).language, "swe")
        // Live Kodi sends `currentsubtitle: {}` when no subtitle is selected.
        XCTAssertNotNil(properties.currentsubtitle)
        XCTAssertEqual(properties.currentsubtitle?.index, 0)
        // The overlay's pickers read these lists; the live box carries one audio
        // stream and no subtitle streams for this item.
        XCTAssertEqual(properties.audiostreams.count, 1)
        XCTAssertEqual(properties.audiostreams.first?.name, "AAC-LC stereo")
        XCTAssertTrue(properties.subtitles.isEmpty)
    }

    func testPlayerPropertiesDecodesStreamLists() throws {
        let properties = try result(PlayerProperties.self, from: #"""
        {"jsonrpc": "2.0", "result": {"audiostreams": [{"index": 0, "name": "Stereo", "language": "eng"}, {"index": 1, "name": "Commentary", "language": "eng"}], "subtitles": [{"index": 0, "name": "English", "language": "eng", "isdefault": true}]}}
        """#)

        XCTAssertEqual(properties.audiostreams.map(\.index), [0, 1])
        XCTAssertEqual(properties.subtitles.map(\.index), [0])
        XCTAssertEqual(properties.subtitles.first?.language, "eng")
    }

    func testPlayerItemFromLiveKodi() throws {
        // Kodi nests this one under `item`, which is what the client unwraps.
        let item = try result(ItemPayload.self, from: Self.livePlayerItem).item

        XCTAssertEqual(item.title, "CL")
        XCTAssertEqual(item.type, "movie")
        XCTAssertEqual(item.runtime, 1810)
        XCTAssertEqual(item.season, -1)
        XCTAssertEqual(item.artists, [])
        XCTAssertEqual(item.subtitleLine, "")
        XCTAssertNotNil(Artwork.poster(for: item.art, thumbnail: item.thumbnail))
    }

    func testPlayerItemDecodesPlotYearGenre() throws {
        let item = try result(ItemPayload.self, from: #"""
        {"jsonrpc": "2.0", "result": {"item": {"title": "Film", "plot": "A plot.", "year": 1999, "genre": ["Drama", "Comedy"]}}}
        """#).item

        XCTAssertEqual(item.plot, "A plot.")
        XCTAssertEqual(item.year, 1999)
        XCTAssertEqual(item.genre.values, ["Drama", "Comedy"])
        XCTAssertEqual(item.infoLine, "1999 · Drama · Comedy")
    }

    func testApplicationPropertiesUnwrapsVersionObject() throws {
        let properties = try result(ApplicationProperties.self, from: Self.liveApplication)

        XCTAssertEqual(properties.name, "Kodi")
        XCTAssertEqual(properties.volume, 50)
        XCTAssertFalse(properties.muted)
        XCTAssertEqual(properties.versionLabel, "21.3-Omega")
    }

    func testMovieListFromLiveKodi() throws {
        let payload = try result(ListPayload.self, from: Self.liveMovies)
        let movies = try XCTUnwrap(payload.movies)

        XCTAssertEqual(payload.limits?.total, 4320)
        XCTAssertEqual(movies.count, 1)
        XCTAssertEqual(movies[0].movieid, 1998)
        XCTAssertEqual(movies[0].year, 2026)
        XCTAssertEqual(movies[0].playableItem?["movieid"] as? Int, 1998)
    }

    func testErrorEnvelopeSurfacesAsRPCError() throws {
        // `System.FriendlyName` is in the Yatse 12.0.0 method table but Kodi 21.3
        // answers -32601, so the client must surface it rather than swallow it.
        let envelope = try JSONDecoder().decode(RPCEnvelope<String>.self,
                                                from: Data(Self.methodNotFound.utf8))
        XCTAssertNil(envelope.result)
        XCTAssertEqual(envelope.error?.code, -32601)
        XCTAssertEqual(envelope.error?.message, "Method not found.")
    }

    // MARK: Lenient decoding

    func testMediaItemAcceptsArtistAsStringOrArray() throws {
        let single = try result(ListPayload.self, from: #"""
        {"jsonrpc": "2.0", "result": {"artists": [{"artistid": 5, "artist": "Radiohead", "label": "Radiohead"}]}}
        """#)
        XCTAssertEqual(single.artists?.first?.artists, ["Radiohead"])

        let multiple = try result(ListPayload.self, from: #"""
        {"jsonrpc": "2.0", "result": {"albums": [{"albumid": 9, "artist": ["Boards of Canada", "Odd Nosdam"], "title": "Album"}]}}
        """#)
        XCTAssertEqual(multiple.albums?.first?.artists, ["Boards of Canada", "Odd Nosdam"])
    }

    func testMediaItemToleratesMissingFields() throws {
        let payload = try result(ListPayload.self, from: #"""
        {"jsonrpc": "2.0", "result": {"episodes": [{"episodeid": 3}]}}
        """#)
        let episode = try XCTUnwrap(payload.episodes?.first)

        XCTAssertEqual(episode.episodeid, 3)
        XCTAssertEqual(episode.heading, "")
        XCTAssertEqual(episode.season, -1)
        XCTAssertNil(episode.movieid)
        XCTAssertEqual(episode.detailLine, "")
    }

    func testPlayerPropertiesToleratesEmptyResult() throws {
        let properties = try result(PlayerProperties.self, from: #"""
        {"jsonrpc": "2.0", "result": {}}
        """#)

        XCTAssertEqual(properties.speed, 0)
        XCTAssertFalse(properties.isPlaying)
        XCTAssertEqual(properties.repeatMode, "off")
        XCTAssertNil(properties.time)
        XCTAssertNil(properties.currentaudiostream)
        XCTAssertTrue(properties.audiostreams.isEmpty)
        XCTAssertTrue(properties.subtitles.isEmpty)
    }

    // MARK: Artwork

    func testArtworkUnwrapsImageSchemeAndPercentEscapes() {
        let url = Artwork.url("image://http%3a%2f%2fhost%3a8080%2fposter.jpg/")
        XCTAssertEqual(url?.absoluteString, "http://host:8080/poster.jpg")
        XCTAssertNil(Artwork.url(""))
    }

    func testArtworkPrefersPosterOverIcon() {
        let art = ["icon": "image://DefaultVideo.png/", "poster": "image://http%3a%2f%2fhost%2fp.jpg/"]
        XCTAssertEqual(Artwork.poster(for: art, thumbnail: "")?.absoluteString, "http://host/p.jpg")
        XCTAssertEqual(Artwork.poster(for: ["icon": "image://DefaultVideo.png/"], thumbnail: "")?
            .absoluteString, "DefaultVideo.png")
        XCTAssertNil(Artwork.poster(for: [:], thumbnail: ""))
    }

    /// Add-on and plugin art decodes to something the device has no route to — a
    /// local file path or a `special://` value — so it is served by the host's own
    /// image endpoint, with the value Kodi sent passed through as it arrived.
    /// Only library art, which is an absolute URL to the media server, goes direct.
    func testAddonArtworkIsServedByTheHostAndLibraryArtworkIsNot() throws {
        var host = Host()
        host.address = "10.13.13.7"
        host.port = 8080

        let icon = try XCTUnwrap(Artwork.url(
            "image://%2fstorage%2f.kodi%2faddons%2fplugin.video.youtube%2ficon.png", host: host))
        XCTAssertEqual(icon.scheme, "http")
        XCTAssertEqual(icon.host, "10.13.13.7")
        XCTAssertEqual(icon.port, 8080)
        XCTAssertEqual(icon.absoluteString,
                       "http://10.13.13.7:8080/image/%2fstorage%2f.kodi%2faddons%2fplugin.video.youtube%2ficon.png")

        XCTAssertEqual(
            Artwork.url("image://special%3a%2f%2fhome%2faddons%2fx.png", host: host)?.absoluteString,
            "http://10.13.13.7:8080/image/special%3a%2f%2fhome%2faddons%2fx.png"
        )

        // Library art is already absolute; it is not routed through the host.
        XCTAssertEqual(
            Artwork.url("image://http%3a%2f%2f10.13.13.2%3a8096%2fposter.jpg/", host: host)?
                .absoluteString,
            "http://10.13.13.2:8096/poster.jpg"
        )

        XCTAssertNil(Artwork.url("", host: host))
    }

    // MARK: Host

    func testHostBuildsEndpoints() {
        var host = Host()
        host.address = "10.13.13.7"
        host.port = 8080

        XCTAssertEqual(host.rpcURL?.absoluteString, "http://10.13.13.7:8080/jsonrpc")
        XCTAssertEqual(host.socketURL?.absoluteString, "ws://10.13.13.7:8080/jsonrpc")

        host.useTLS = true
        XCTAssertEqual(host.rpcURL?.absoluteString, "https://10.13.13.7:8080/jsonrpc")
        XCTAssertEqual(host.socketURL?.absoluteString, "wss://10.13.13.7:8080/jsonrpc")

        host.address = ""
        XCTAssertFalse(host.isUsable)
        XCTAssertNil(host.rpcURL)
    }

    func testWakeOnLanRejectsMalformedMAC() {
        var host = Host()
        host.address = "10.0.0.5"
        host.macAddress = "not-a-mac"

        XCTAssertThrowsError(try host.wake()) { error in
            XCTAssertEqual((error as? Host.WakeError)?.errorDescription,
                           "MAC address must be 12 hex digits, e.g. AA:BB:CC:DD:EE:FF")
        }
    }

    // MARK: Notifications

    func testOnlyNotificationsCountAsEvents() {
        let client = KodiClient(host: Host(name: "t", address: "127.0.0.1", port: 8080),
                               username: "",
                               password: "")

        XCTAssertEqual(
            client.notificationName(in: #"{"jsonrpc":"2.0","method":"Player.OnPlay","params":{"data":{}}}"#),
            "Player.OnPlay"
        )
        XCTAssertNil(client.notificationName(in: #"{"id":1,"jsonrpc":"2.0","result":"OK"}"#))
        XCTAssertNil(client.notificationName(in: "not json"))
    }

    // MARK: Library routing

    func testSectionsRouteToTheirResultKeys() throws {
        XCTAssertEqual(LibrarySection.movies.method, "VideoLibrary.GetMovies")
        XCTAssertEqual(LibrarySection.artists.sortMethod, "artist")
        XCTAssertEqual(LibrarySection.tvshows.properties.contains("thumbnail"), true)

        let payload = try result(ListPayload.self, from: Self.liveMovies)
        XCTAssertEqual(LibrarySection.movies.items(from: payload).count, 1)
        XCTAssertEqual(LibrarySection.tvshows.items(from: payload).count, 0)
    }

    func testChildrenRequestsCarryTheirParentID() {
        XCTAssertEqual(ChildrenRequest.episodes(tvshowID: 12).params["tvshowid"] as? Int, 12)
        XCTAssertEqual(ChildrenRequest.albumsOfArtist(artistID: 7).params["artistid"] as? Int, 7)
        XCTAssertEqual(ChildrenRequest.episodes(tvshowID: 12).method, "VideoLibrary.GetEpisodes")
    }

    // MARK: Add-ons

    /// Captured from the live host (`Addons.GetAddons`, Kodi 21.3), which is how
    /// we know `enabled` is a real boolean rather than the "true"/"false" string
    /// older builds sent — and that a video add-on reports
    /// `xbmc.python.pluginsource`. An earlier version of this fixture said
    /// `xbmc.addon.video`; that type does not occur on the box at all, which is
    /// exactly how a filter on it would have drawn an empty screen.
    static let liveAddons = """
    {"jsonrpc":"2.0","id":1,"result":{"addons":[
      {"addonid":"plugin.video.youtube","type":"xbmc.python.pluginsource","enabled":true,
       "name":"YouTube","version":"7.0.1","summary":"YouTube","description":"d",
       "thumbnail":"image://%2fstorage%2f.kodi%2faddons%2fplugin.video.youtube%2ficon.png",
       "author":"team","broken":false},
      {"addonid":"script.module.requests","type":"xbmc.python.module","enabled":false,
       "name":"Requests","version":"2.31.0","summary":"s","description":"d",
       "thumbnail":"","author":"team","broken":false},
      {"addonid":"script.pystone.benchmark","type":"xbmc.python.pluginsource","enabled":true,
       "name":"CPU Benchmark","version":"1.0.0","summary":"s","description":"d",
       "thumbnail":"","author":"team","broken":false},
      {"addonid":"skin.estuary","type":"xbmc.gui.skin","enabled":true,
       "name":"Estuary","version":"1.0.0","summary":"s","description":"d",
       "thumbnail":"","author":"team","broken":false}
    ],"limits":{"start":0,"end":4,"total":4}}}
    """

    func testAddonsDecodeTheLiveResponse() throws {
        let payload = try result(ListPayload.self, from: Self.liveAddons)
        let addons = try XCTUnwrap(payload.addons)
        XCTAssertEqual(addons.count, 4)

        let youtube = try XCTUnwrap(addons.first)
        XCTAssertEqual(youtube.addonid, "plugin.video.youtube")
        XCTAssertEqual(youtube.displayName, "YouTube")
        XCTAssertTrue(youtube.enabled)
        XCTAssertFalse(youtube.broken)
        XCTAssertTrue(youtube.isVideoAddon)
    }

    /// Only video add-ons reach the Addons destination. The measured trap: the
    /// live host answers `xbmc.python.pluginsource` for every video add-on and
    /// never `xbmc.addon.video` — 0 of its 68 add-ons — so a predicate on that
    /// type lists nothing at all. This asserts the rule against the values the
    /// host actually sends.
    func testOnlyVideoAddonsAreListed() throws {
        let payload = try result(ListPayload.self, from: Self.liveAddons)
        let listed = try XCTUnwrap(payload.addons).filter(\.isVideoAddon)

        XCTAssertEqual(listed.map(\.addonid), ["plugin.video.youtube"])

        // A plugin source that is not a video add-on, a skin and a module.
        XCTAssertFalse(Addon(addonid: "script.pystone.benchmark",
                             type: "xbmc.python.pluginsource").isVideoAddon)
        XCTAssertFalse(Addon(addonid: "skin.estuary", type: "xbmc.gui.skin").isVideoAddon)
        XCTAssertFalse(Addon(addonid: "script.module.requests",
                             type: "xbmc.python.module").isVideoAddon)

        // The video namespace is what decides it, not the plugin-source type
        // alone — an audio plugin source is not a video add-on.
        XCTAssertFalse(Addon(addonid: "plugin.audio.spotify",
                             type: "xbmc.python.pluginsource").isVideoAddon)
        XCTAssertTrue(Addon(addonid: "plugin.video.jellycon",
                            type: "xbmc.python.pluginsource").isVideoAddon)
    }

    /// A disabled add-on must stay decodable and listed, because the only way to
    /// turn it back on is the action offered on it.
    func testDisabledAddonDecodesAsDisabled() throws {
        let payload = try result(ListPayload.self, from: Self.liveAddons)
        let disabled = try XCTUnwrap(payload.addons?.first { !$0.enabled })
        XCTAssertEqual(disabled.addonid, "script.module.requests")
        XCTAssertEqual(disabled.displayName, "Requests")
    }

    func testAddonFieldsAreOptional() throws {
        // Only addonid is guaranteed; a missing name falls back to the id.
        let payload = try result(ListPayload.self, from:
            #"{"jsonrpc":"2.0","id":1,"result":{"addons":[{"addonid":"x.y.z"}],"limits":{"start":0,"end":1,"total":1}}}"#)
        let addon = try XCTUnwrap(payload.addons?.first)
        XCTAssertEqual(addon.displayName, "x.y.z")
        XCTAssertFalse(addon.isVideoAddon)
        XCTAssertFalse(addon.enabled)
    }

    // MARK: Directories

    /// The `Files.GetDirectory` shape from the live host: folders carry
    /// `filetype: "directory"`, leaves do not, and each entry carries the `file`
    /// path that both drill-down and playback need.
    func testDirectoryEntriesReportWhetherTheyAreFolders() throws {
        let json = """
        {"jsonrpc":"2.0","id":1,"result":{"files":[
          {"file":"smb://nas/films/","filetype":"directory","label":"Films","type":"directory"},
          {"file":"smb://nas/film.mkv","filetype":"file","label":"Film","type":"movie"}
        ],"limits":{"start":0,"end":2,"total":2}}}
        """
        let payload = try result(ListPayload.self, from: json)
        let files = try XCTUnwrap(payload.files)
        XCTAssertTrue(files[0].isDirectory)
        XCTAssertFalse(files[1].isDirectory)
        XCTAssertEqual(files[0].heading, "Films")
        XCTAssertEqual(files[1].playableItem?["file"] as? String, "smb://nas/film.mkv")
    }

    func testSourcesDecodeWithTheirLabel() throws {
        let json = """
        {"jsonrpc":"2.0","id":1,"result":{"sources":[
          {"file":"smb://nas/films/","label":"Films"}
        ],"limits":{"start":0,"end":1,"total":1}}}
        """
        let payload = try result(ListPayload.self, from: json)
        XCTAssertEqual(payload.sources?.first?.label, "Films")
        XCTAssertEqual(payload.sources?.first?.file, "smb://nas/films/")
    }

    // MARK: Files.GetDirectory request shape

    /// `filetype` and `label` are output-only. Kodi returns both whether or not
    /// they are asked for, and naming either in `properties` makes it reject the
    /// whole call with -32602 — indistinguishable from a missing plugin, which
    /// is exactly how the Files browser looked broken against the live box.
    func testDirectoryPropertiesOmitOutputOnlyFields() {
        XCTAssertFalse(KodiClient.directoryProperties.contains("filetype"))
        XCTAssertFalse(KodiClient.directoryProperties.contains("label"))
        XCTAssertTrue(KodiClient.directoryProperties.contains("file"))
        XCTAssertTrue(KodiClient.directoryProperties.contains("thumbnail"))
    }

    // MARK: Kodi text markup

    func testKodiMarkupIsStrippedFromLabels() {
        XCTAssertEqual("[B]My Subscriptions[/B]".strippingKodiMarkup, "My Subscriptions")
        XCTAssertEqual("[COLOR yellow]Trending[/COLOR]".strippingKodiMarkup, "Trending")
        XCTAssertEqual("[I][U]Both[/U][/I]".strippingKodiMarkup, "Both")
        XCTAssertEqual("[CR]Search".strippingKodiMarkup, "Search")
    }

    /// Only real Kodi tags are removed — a title with legitimate brackets stays.
    func testBracketedTitlesSurviveStripping() {
        XCTAssertEqual("[REC]".strippingKodiMarkup, "[REC]")
        XCTAssertEqual("Movie [2019]".strippingKodiMarkup, "Movie [2019]")
    }

    func testHeadingIsStrippedForDisplay() throws {
        let json = """
        {"jsonrpc":"2.0","id":1,"result":{"files":[
          {"file":"plugin://plugin.video.youtube/special/x","filetype":"directory",
           "label":"[B]My Subscriptions[/B]","type":"unknown"}
        ],"limits":{"start":0,"end":1,"total":1}}}
        """
        let payload = try result(ListPayload.self, from: json)
        XCTAssertEqual(payload.files?.first?.heading, "My Subscriptions")
    }

    // MARK: Add-ons

    func testOnlyPluginAddonsOfferBrowsing() {
        let plugin = Addon(addonid: "plugin.video.youtube", type: "xbmc.python.pluginsource")
        XCTAssertTrue(plugin.isBrowsable)
        XCTAssertEqual(plugin.browsePath, "plugin://plugin.video.youtube/")

        // Nothing to browse in a skin, a scraper or a font.
        XCTAssertFalse(Addon(addonid: "skin.estuary", type: "xbmc.gui.skin").isBrowsable)
        XCTAssertFalse(Addon(addonid: "metadata.x", type: "xbmc.metadata.scraper.movies").isBrowsable)
        XCTAssertFalse(Addon(addonid: "resource.images.x", type: "kodi.resource.images").isBrowsable)
    }
}
