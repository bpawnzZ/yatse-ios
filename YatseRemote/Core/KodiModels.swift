import Foundation

/// Kodi's JSON-RPC schemas are loose: a field is present only when it applies to
/// the item type and only when it was requested. Every model below therefore
/// decodes leniently — a missing or mistyped key yields a default instead of
/// failing the whole response.
func lenient<T: Decodable, K: CodingKey>(
    _ container: KeyedDecodingContainer<K>, _ key: K, _ fallback: T
) -> T {
    ((try? container.decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
}

/// Accepts both `"artist": "Radiohead"` (AudioLibrary.GetArtists) and
/// `"artist": ["Radiohead"]` (AudioLibrary.GetSongs/GetAlbums).
struct StringList: Decodable, Hashable {
    var values: [String] = []

    init(values: [String] = []) { self.values = values }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let array = try? container.decode([String].self) {
            values = array
        } else if let single = try? container.decode(String.self) {
            values = single.isEmpty ? [] : [single]
        }
    }
}

// MARK: - JSON-RPC envelope

struct RPCError: Decodable, LocalizedError {
    let code: Int
    let message: String
    var errorDescription: String? { message }
}

struct RPCEnvelope<T: Decodable>: Decodable {
    let result: T?
    let error: RPCError?
}

/// A JSON-RPC result the caller does not read. Kodi answers some methods with
/// `"OK"` and others with a boolean (`GUI.SetFullscreen`), so a command path that
/// decodes into a concrete type throws `malformedResponse` on the methods whose
/// result shape differs. Decoding into this accepts any payload while still
/// surfacing a JSON-RPC error object.
struct IgnoreResult: Decodable {
    init() {}
    init(from decoder: Decoder) throws {}
}

// MARK: - Player

struct ActivePlayer: Decodable, Identifiable, Hashable {
    let playerid: Int
    let type: String
    var id: Int { playerid }
    var isAudio: Bool { type == "audio" }
    var isVideo: Bool { type == "video" }
}

struct KodiDuration: Decodable, Hashable {
    var hours = 0
    var minutes = 0
    var seconds = 0
    var milliseconds = 0

    var totalSeconds: Double {
        Double(hours) * 3600 + Double(minutes) * 60 + Double(seconds) + Double(milliseconds) / 1000
    }

    enum CodingKeys: String, CodingKey { case hours, minutes, seconds, milliseconds }
}

extension KodiDuration {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hours = lenient(container, .hours, 0)
        minutes = lenient(container, .minutes, 0)
        seconds = lenient(container, .seconds, 0)
        milliseconds = lenient(container, .milliseconds, 0)
    }
}

struct AudioStream: Decodable, Hashable {
    var index = 0
    var name = ""
    var language = ""
    var codec = ""
    var channels = 0
    var isdefault = false

    enum CodingKeys: String, CodingKey { case index, name, language, codec, channels, isdefault }
}

extension AudioStream {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = lenient(container, .index, 0)
        name = lenient(container, .name, "")
        language = lenient(container, .language, "")
        codec = lenient(container, .codec, "")
        channels = lenient(container, .channels, 0)
        isdefault = lenient(container, .isdefault, false)
    }
}

struct SubtitleStream: Decodable, Hashable {
    var index = 0
    var name = ""
    var language = ""
    var isdefault = false
    var isforced = false
    var isimpaired = false

    enum CodingKeys: String, CodingKey {
        case index, name, language, isdefault, isforced, isimpaired
    }
}

extension SubtitleStream {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = lenient(container, .index, 0)
        name = lenient(container, .name, "")
        language = lenient(container, .language, "")
        isdefault = lenient(container, .isdefault, false)
        isforced = lenient(container, .isforced, false)
        isimpaired = lenient(container, .isimpaired, false)
    }
}

struct PlayerProperties: Decodable {
    var speed = 0
    var percentage = 0.0
    var position = -1
    var playlistid = -1
    var repeatMode = "off"
    var shuffled = false
    var partymode = false
    var time: KodiDuration?
    var totaltime: KodiDuration?
    var currentaudiostream: AudioStream?
    var currentsubtitle: SubtitleStream?
    /// The full lists the Now Playing overlay's pickers are built from. Kodi
    /// returns them alongside the current streams, so no extra call is needed.
    var audiostreams: [AudioStream] = []
    var subtitles: [SubtitleStream] = []

    var isPlaying: Bool { speed != 0 }

    enum CodingKeys: String, CodingKey {
        case speed, percentage, position, playlistid, shuffled, partymode
        case time, totaltime, currentaudiostream, currentsubtitle
        case audiostreams, subtitles
        case repeatMode = "repeat"
    }
}

extension PlayerProperties {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        speed = lenient(container, .speed, 0)
        percentage = lenient(container, .percentage, 0)
        position = lenient(container, .position, -1)
        playlistid = lenient(container, .playlistid, -1)
        repeatMode = lenient(container, .repeatMode, "off")
        shuffled = lenient(container, .shuffled, false)
        partymode = lenient(container, .partymode, false)
        time = (try? container.decodeIfPresent(KodiDuration.self, forKey: .time)) ?? nil
        totaltime = (try? container.decodeIfPresent(KodiDuration.self, forKey: .totaltime)) ?? nil
        currentaudiostream = (try? container.decodeIfPresent(AudioStream.self, forKey: .currentaudiostream)) ?? nil
        currentsubtitle = (try? container.decodeIfPresent(SubtitleStream.self, forKey: .currentsubtitle)) ?? nil
        audiostreams = lenient(container, .audiostreams, [])
        subtitles = lenient(container, .subtitles, [])
    }
}

// MARK: - Items

/// `Player.GetItem` nests its payload: `result` is `{"item": {...}}`.
struct ItemPayload: Decodable {
    let item: PlayerItem
}

/// `Player.GetItem` result and library rows share this shape.
struct PlayerItem: Decodable {
    var id: Int?
    var label = ""
    var type = ""
    var title = ""
    var showtitle = ""
    var album = ""
    var artist = StringList()
    var thumbnail = ""
    var fanart = ""
    var art: [String: String] = [:]
    var season = -1
    var episode = -1
    var runtime = 0
    var file = ""
    /// Shown in the Now Playing overlay's info view.
    var plot = ""
    var year = 0
    var genre = StringList()

    var artists: [String] { artist.values }
    var subtitleLine: String {
        if !showtitle.isEmpty {
            let seasonEpisode = season >= 0 && episode >= 0
                ? String(format: "S%02dE%02d", season, episode)
                : ""
            return [showtitle, seasonEpisode].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return artists.joined(separator: ", ")
    }

    /// Year and genres joined for the info view, empty when neither is present.
    var infoLine: String {
        var parts: [String] = []
        if year > 0 { parts.append(String(year)) }
        parts.append(contentsOf: genre.values)
        return parts.joined(separator: " · ")
    }

    enum CodingKeys: String, CodingKey {
        case id, label, type, title, showtitle, album, artist, thumbnail, fanart
        case art, season, episode, runtime, file, plot, year, genre
    }
}

extension PlayerItem {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(Int.self, forKey: .id)) ?? nil
        label = lenient(container, .label, "")
        type = lenient(container, .type, "")
        title = lenient(container, .title, "")
        showtitle = lenient(container, .showtitle, "")
        album = lenient(container, .album, "")
        artist = lenient(container, .artist, StringList())
        thumbnail = lenient(container, .thumbnail, "")
        fanart = lenient(container, .fanart, "")
        art = lenient(container, .art, [:])
        season = lenient(container, .season, -1)
        episode = lenient(container, .episode, -1)
        runtime = lenient(container, .runtime, 0)
        file = lenient(container, .file, "")
        plot = lenient(container, .plot, "")
        year = lenient(container, .year, 0)
        genre = lenient(container, .genre, StringList())
    }
}

/// A row from any list-returning method (library, playlist, sources).
struct MediaItem: Decodable {
    var id: Int?
    var label = ""
    var title = ""
    var type = ""
    var showtitle = ""
    var album = ""
    var artist = StringList()
    var thumbnail = ""
    var fanart = ""
    var art: [String: String] = [:]
    var year = 0
    var runtime = 0
    var playcount = 0
    var season = -1
    var episode = -1
    var file = ""
    var filetype = ""

    /// Directory entries from `Files.GetDirectory` carry a `filetype`; anything
    /// else is a leaf that can be played.
    var isDirectory: Bool { filetype == "directory" }

    var movieid: Int?
    var tvshowid: Int?
    var episodeid: Int?
    var artistid: Int?
    var albumid: Int?
    var songid: Int?

    var artists: [String] { artist.values }

    var heading: String { (title.isEmpty ? label : title).strippingKodiMarkup }

    var detailLine: String {
        if !showtitle.isEmpty {
            let numbering = season >= 0 && episode >= 0
                ? String(format: "S%02dE%02d", season, episode)
                : ""
            return [showtitle, numbering].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        if !artists.isEmpty { return artists.joined(separator: ", ") }
        if !album.isEmpty { return album }
        if year > 0 { return String(year) }
        return ""
    }

    enum CodingKeys: String, CodingKey {
        case id, label, title, type, showtitle, album, artist, thumbnail, fanart
        case art, year, runtime, playcount, season, episode, file, filetype
        case movieid, tvshowid, episodeid, artistid, albumid, songid
    }
}

extension MediaItem {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(Int.self, forKey: .id)) ?? nil
        label = lenient(container, .label, "")
        title = lenient(container, .title, "")
        type = lenient(container, .type, "")
        showtitle = lenient(container, .showtitle, "")
        album = lenient(container, .album, "")
        artist = lenient(container, .artist, StringList())
        thumbnail = lenient(container, .thumbnail, "")
        fanart = lenient(container, .fanart, "")
        art = lenient(container, .art, [:])
        year = lenient(container, .year, 0)
        runtime = lenient(container, .runtime, 0)
        playcount = lenient(container, .playcount, 0)
        season = lenient(container, .season, -1)
        episode = lenient(container, .episode, -1)
        file = lenient(container, .file, "")
        filetype = lenient(container, .filetype, "")
        movieid = (try? container.decodeIfPresent(Int.self, forKey: .movieid)) ?? nil
        tvshowid = (try? container.decodeIfPresent(Int.self, forKey: .tvshowid)) ?? nil
        episodeid = (try? container.decodeIfPresent(Int.self, forKey: .episodeid)) ?? nil
        artistid = (try? container.decodeIfPresent(Int.self, forKey: .artistid)) ?? nil
        albumid = (try? container.decodeIfPresent(Int.self, forKey: .albumid)) ?? nil
        songid = (try? container.decodeIfPresent(Int.self, forKey: .songid)) ?? nil
    }
}

/// One type for every list-returning method; the caller reads the key it asked for.
struct ListPayload: Decodable {
    struct Limits: Decodable {
        var start = 0
        var end = 0
        var total = 0
        enum CodingKeys: String, CodingKey { case start, end, total }
    }

    var limits: Limits?
    var movies: [MediaItem]?
    var sets: [MediaItem]?
    var tvshows: [MediaItem]?
    var seasons: [MediaItem]?
    var episodes: [MediaItem]?
    var artists: [MediaItem]?
    var albums: [MediaItem]?
    var songs: [MediaItem]?
    var genres: [MediaItem]?
    var items: [MediaItem]?
    var sources: [MediaItem]?
    var files: [MediaItem]?
    var addons: [Addon]?
}

// MARK: - Kodi text markup

extension String {
    /// Plugin listings come back with Kodi's own markup in the label — the live
    /// YouTube addon answers `[B]My Subscriptions[/B]`. Stripped for display.
    ///
    /// Restricted to real Kodi tags rather than any `[word]`, so a title that
    /// legitimately contains brackets (`[REC]`) survives.
    var strippingKodiMarkup: String {
        replacingOccurrences(
            of: #"\[/?(?:B|I|U|S|CR|COLOR|LIGHT|LOWERCASE|UPPERCASE|CAPITALIZE|FONT|SIZE|URL|IMG)[^\]]*\]"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }
}

// MARK: - Add-ons

/// An installed add-on. `enabled` and `broken` are real booleans on Kodi 19+ —
/// confirmed against Kodi 21.3 (/jsonrpc, Addons.GetAddons) rather than assumed,
/// because the pre-19 wire format answered with "true"/"false" strings. A string
/// here falls back to the default rather than failing the page.
struct Addon: Decodable, Identifiable, Hashable {
    var addonid = ""
    var type = ""
    var name = ""
    var version = ""
    var summary = ""
    var description = ""
    var thumbnail = ""
    var author = ""
    var broken = false
    var enabled = false

    var id: String { addonid }

    var displayName: String { name.isEmpty ? addonid : name }

    /// Add-on types whose content Kodi exposes as a browsable virtual path.
    ///
    /// Verified against the live box: `Files.GetDirectory` on
    /// `plugin://<addonid>/` returns real entries for plugin sources (the YouTube
    /// addon answered 21 of them). A skin, scraper or font has no such tree, so
    /// offering to browse one would only produce Kodi's error.
    var isBrowsable: Bool {
        ["xbmc.python.pluginsource", "xbmc.addon.video", "xbmc.addon.audio",
         "xbmc.addon.image", "kodi.addon.game"].contains(type)
    }

    /// Whether this is a video add-on — which is all the Addons destination lists.
    ///
    /// The identifier namespace is what actually separates them. Measured on the
    /// live host: every video add-on answers `type: "xbmc.python.pluginsource"`
    /// and `xbmc.addon.video` does not occur at all — 0 of the 68 installed
    /// add-ons — so a predicate on that type draws an empty screen rather than
    /// failing loudly. `plugin.video.*` is Kodi's convention for a video plugin;
    /// `script.pystone.benchmark` is a plugin source that is not one.
    var isVideoAddon: Bool {
        isBrowsable && addonid.hasPrefix("plugin.video.")
    }

    /// Where this add-on's content lives, for `Files.GetDirectory`.
    var browsePath: String { "plugin://\(addonid)/" }

    enum CodingKeys: String, CodingKey {
        case addonid, type, name, version, summary, description, thumbnail, author
        case broken, enabled
    }
}

extension Addon {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        addonid = lenient(container, .addonid, "")
        type = lenient(container, .type, "")
        name = lenient(container, .name, "")
        version = lenient(container, .version, "")
        summary = lenient(container, .summary, "")
        description = lenient(container, .description, "")
        thumbnail = lenient(container, .thumbnail, "")
        author = lenient(container, .author, "")
        broken = lenient(container, .broken, false)
        enabled = lenient(container, .enabled, false)
    }
}

// MARK: - Artwork

enum Artwork {
    /// Kodi hands back `image://` URLs that may be percent-encoded remote art or
    /// a texture cache reference. Strip the scheme and decode so URLSession can
    /// fetch it (Kodi re-encodes and proxies the actual image).
    static func url(_ raw: String) -> URL? {
        guard !raw.isEmpty else { return nil }
        var value = raw
        if value.hasPrefix("image://") {
            value = String(value.dropFirst("image://".count))
        }
        if value.hasSuffix("/") { value.removeLast() }
        let decoded = value.removingPercentEncoding ?? value
        return URL(string: decoded)
    }

    /// Best available poster for a row, preferring explicit art keys.
    static func poster(for art: [String: String], thumbnail: String) -> URL? {
        for key in ["poster", "thumb", "cover", "fanart", "banner", "icon"] {
            if let raw = art[key], let url = url(raw) { return url }
        }
        return url(thumbnail)
    }

    /// The same value, served by the connected host's own image endpoint.
    ///
    /// One shape works for every value Kodi hands out, measured on the live box:
    /// **the whole value — `image://` scheme and Kodi's trailing slash included —
    /// percent-encoded a second time as one path segment.**
    /// `/image/image%3A%2F%2Fhttps%253a%252f…` is the cached JPEG (200, 22,662 B);
    /// `/image/https%3a%2f%2f…` (scheme stripped, decoded) and
    /// `/image/image://https%3a…` are both **404**. The same double-encoded form
    /// answered 200 for all 63 add-on icons and every library poster, which is
    /// why it is the one rule rather than a per-shape special case.
    ///
    /// This is the route that does not depend on the *device* being able to reach
    /// the server behind the artwork: library art points at the Plex/Jellyfin
    /// address and add-on art points at a path the phone has no route to at all.
    /// Ceiling: the host serves out of its texture cache, so an image Kodi has
    /// never rendered is a 404 here — `urls(_:host:)` keeps the direct URL for
    /// exactly that case.
    static func url(_ raw: String, host: Host) -> URL? {
        // The same character set the measured request used: everything except
        // the RFC 3986 unreserved characters is escaped.
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard !raw.isEmpty,
              let encoded = raw.addingPercentEncoding(withAllowedCharacters: unreserved),
              var components = host.rpcURL.flatMap({
                  URLComponents(url: $0, resolvingAgainstBaseURL: false)
              }) else { return nil }

        components.percentEncodedPath = "/image/" + encoded
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// Every URL to try for one artwork value, in order: the host's copy first,
    /// then whatever the device could fetch by itself.
    static func urls(_ raw: String, host: Host?) -> [URL] {
        var candidates: [URL] = []
        if let host, let served = url(raw, host: host) { candidates.append(served) }
        if let direct = url(raw), !candidates.contains(direct) { candidates.append(direct) }
        return candidates
    }

    /// Best available poster for a row that may carry add-on or plugin artwork.
    static func posterURLs(for art: [String: String], thumbnail: String, host: Host?) -> [URL] {
        for key in ["poster", "thumb", "cover", "fanart", "banner", "icon"] {
            if let raw = art[key] {
                let candidates = urls(raw, host: host)
                if !candidates.isEmpty { return candidates }
            }
        }
        return urls(thumbnail, host: host)
    }
}
