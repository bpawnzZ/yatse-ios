import Foundation

/// How a section's results are laid out. Poster media reads as a grid; text
/// media reads as a list. Kept with the section so the browser does not decide.
enum LibraryLayout: Equatable {
    case grid
    case list
}

/// The library tabs. Method names, property lists and sort methods are the ones
/// recovered from the Yatse 12.0.0 DEX and validated live against Kodi 21.3.
enum LibrarySection: String, CaseIterable, Identifiable {
    case movies
    case tvshows
    case artists
    case albums

    var id: String { rawValue }

    var title: String {
        switch self {
        case .movies: return "Movies"
        case .tvshows: return "TV Shows"
        case .artists: return "Artists"
        case .albums: return "Albums"
        }
    }

    var method: String {
        switch self {
        case .movies: return "VideoLibrary.GetMovies"
        case .tvshows: return "VideoLibrary.GetTVShows"
        case .artists: return "AudioLibrary.GetArtists"
        case .albums: return "AudioLibrary.GetAlbums"
        }
    }

    var properties: [String] {
        switch self {
        case .movies: return ["title", "year", "thumbnail", "art", "runtime", "playcount"]
        case .tvshows: return ["title", "thumbnail", "art", "year", "playcount"]
        case .artists: return ["thumbnail", "art", "genre"]
        case .albums: return ["title", "artist", "thumbnail", "art", "year"]
        }
    }

    var sortMethod: String {
        switch self {
        case .movies, .tvshows, .albums: return "title"
        case .artists: return "artist"
        }
    }

    var emptyMessage: String {
        switch self {
        case .movies: return "No movies in this library."
        case .tvshows: return "No TV shows in this library."
        case .artists: return "No artists in this library."
        case .albums: return "No albums in this library."
        }
    }

    /// Poster media browses as a grid; media read as text browses as a list.
    var layout: LibraryLayout {
        switch self {
        case .movies, .tvshows: return .grid
        case .artists, .albums: return .list
        }
    }

    func items(from payload: ListPayload) -> [MediaItem] {
        switch self {
        case .movies: return payload.movies ?? []
        case .tvshows: return payload.tvshows ?? []
        case .artists: return payload.artists ?? []
        case .albums: return payload.albums ?? []
        }
    }

    /// Rows that drill down instead of playing directly.
    func childRequest(for item: MediaItem) -> ChildrenRequest? {
        switch self {
        case .tvshows:
            return item.tvshowid.map { .episodes(tvshowID: $0) }
        case .artists:
            return item.artistid.map { .albumsOfArtist(artistID: $0) }
        case .movies, .albums:
            return nil
        }
    }
}

/// A drill-down list: episodes of a show, albums of an artist.
enum ChildrenRequest: Hashable {
    case episodes(tvshowID: Int)
    case albumsOfArtist(artistID: Int)

    var title: String {
        switch self {
        case .episodes: return "Episodes"
        case .albumsOfArtist: return "Albums"
        }
    }

    var method: String {
        switch self {
        case .episodes: return "VideoLibrary.GetEpisodes"
        case .albumsOfArtist: return "AudioLibrary.GetAlbums"
        }
    }

    var params: [String: Any] {
        switch self {
        case .episodes(let tvshowID):
            return [
                "tvshowid": tvshowID,
                "properties": ["title", "showtitle", "season", "episode", "thumbnail", "art", "runtime", "playcount"],
                "sort": ["method": "episode", "order": "ascending"],
            ]
        case .albumsOfArtist(let artistID):
            return [
                "artistid": artistID,
                "properties": ["title", "artist", "thumbnail", "art", "year"],
                "sort": ["method": "title", "order": "ascending"],
            ]
        }
    }

    func items(from payload: ListPayload) -> [MediaItem] {
        switch self {
        case .episodes: return payload.episodes ?? []
        case .albumsOfArtist: return payload.albums ?? []
        }
    }
}

extension MediaItem {
    /// The `Player.Open` item payload for this row.
    var playableItem: [String: Any]? {
        if let movieid { return ["movieid": movieid] }
        if let episodeid { return ["episodeid": episodeid] }
        if let songid { return ["songid": songid] }
        if let albumid { return ["albumid": albumid] }
        if !file.isEmpty { return ["file": file] }
        return nil
    }
}
