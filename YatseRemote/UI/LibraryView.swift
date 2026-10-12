import SwiftUI

/// Browses one library section. Poster media (Movies, TV Shows) is a two-column
/// grid of poster tiles; media read as text (Artists, Albums) stays a list. The
/// two share pagination, refresh and the empty/error state, so there is still
/// one browser — only the layout differs.
struct LibraryView: View {
    @ObservedObject var model: AppModel
    let section: LibrarySection
    var onOpenDrawer: (() -> Void)? = nil

    @State private var items: [MediaItem] = []
    @State private var total = 0
    @State private var isLoading = false
    @State private var error: String?

    private let pageSize = 60

    var body: some View {
        Group {
            switch section.layout {
            case .grid: grid
            case .list: list
            }
        }
        .overlay { emptyState }
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onOpenDrawer {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { onOpenDrawer() } label: { Image(systemName: "line.3.horizontal") }
                        .accessibilityLabel("Open menu")
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                FavoriteButton(title: section.title, target: .section(section.rawValue))
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh")
            }
        }
        .themedScreen()
        .task { await reload() }
    }

    // MARK: Layouts

    private var list: some View {
        List {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                listRow(for: item)
                    .onAppear { loadMoreIfNeeded(index) }
            }

            if isLoading && !items.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .listStyle(.plain)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ],
                spacing: 16
            ) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    gridCell(for: item)
                        .onAppear { loadMoreIfNeeded(index) }
                }

                if isLoading && !items.isEmpty {
                    ProgressView().gridCellColumns(2)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if items.isEmpty {
            if isLoading {
                ProgressView()
            } else {
                Text(error ?? section.emptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
    }

    // MARK: Rows and cells

    @ViewBuilder
    private func listRow(for item: MediaItem) -> some View {
        if let child = section.childRequest(for: item) {
            NavigationLink {
                ChildrenView(model: model, request: child, heading: item.heading,
                             onOpenDrawer: onOpenDrawer)
            } label: {
                MediaRow(item: item, username: model.host.username, password: model.password, showsChevron: true)
            }
        } else {
            Button {
                Task { await play(item) }
            } label: {
                MediaRow(item: item, username: model.host.username, password: model.password)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func gridCell(for item: MediaItem) -> some View {
        if let child = section.childRequest(for: item) {
            NavigationLink {
                ChildrenView(model: model, request: child, heading: item.heading,
                             onOpenDrawer: onOpenDrawer)
            } label: {
                PosterTile(item: item, username: model.host.username, password: model.password)
            }
        } else {
            Button {
                Task { await play(item) }
            } label: {
                PosterTile(item: item, username: model.host.username, password: model.password)
            }
            .buttonStyle(.plain)
        }
    }

    private func loadMoreIfNeeded(_ index: Int) {
        if index >= items.count - 5 {
            Task { await loadMore() }
        }
    }

    private func play(_ item: MediaItem) async {
        guard let payload = item.playableItem else { return }
        await model.play(item: payload)
    }

    private func reload() async {
        items = []
        total = 0
        error = nil
        await loadMore()
    }

    private func loadMore() async {
        guard !isLoading else { return }
        guard items.isEmpty || items.count < total else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await model.libraryPage(section, offset: items.count, pageSize: pageSize)
            items.append(contentsOf: page.items)
            total = page.total
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// A toolbar star that saves the place you are looking at. Filled means it is
/// already saved. Shared by the library, the drill-downs and the directory
/// browser, so "favourite" means one thing in the app.
struct FavoriteButton: View {
    let title: String
    let target: FavoriteTarget

    @EnvironmentObject private var favorites: FavoriteStore

    var body: some View {
        let saved = favorites.contains(target)
        Button {
            let favorite = Favorite(title: title, target: target)
            if saved {
                favorites.remove(favorite)
            } else {
                favorites.toggle(favorite)
            }
        } label: {
            Image(systemName: saved ? "star.fill" : "star")
        }
        .accessibilityLabel(saved ? "Remove favorite" : "Add favorite")
    }
}

/// One grid tile: poster artwork with the title and detail line beneath.
///
/// Parameterised rather than `MediaItem`-typed so the add-on, favourite and
/// library grids all render the same tile. The alternative was a second tile
/// type, free to drift from this one — which is how the Movies tile once went
/// blank.
struct PosterTile: View {
    let url: URL?
    let title: String
    let detail: String
    let username: String
    let password: String

    init(url: URL?, title: String, detail: String, username: String, password: String) {
        self.url = url
        self.title = title
        self.detail = detail
        self.username = username
        self.password = password
    }

    /// The library grid's tile: artwork and text come from the item.
    init(item: MediaItem, username: String, password: String) {
        self.init(url: Artwork.poster(for: item.art, thumbnail: item.thumbnail),
                  title: item.heading,
                  detail: item.detailLine,
                  username: username,
                  password: password)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterImage(url: url, username: username, password: password)
            Text(title)
                .font(.subheadline)
                .lineLimit(2)
                .foregroundStyle(.primary)
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }
}

/// The long-press menu item that saves a place, or removes it when it is already
/// saved. Shared by the add-on grid, the library rows and the folders inside an
/// add-on, so a long press means one thing everywhere.
struct FavoriteMenuItem: View {
    let favorite: Favorite

    @EnvironmentObject private var favorites: FavoriteStore

    var body: some View {
        let saved = favorites.contains(favorite.target)
        Button(saved ? "Remove favorite" : "Add to Favorites",
               systemImage: saved ? "star.slash" : "star") {
            if saved {
                favorites.remove(favorite)
            } else {
                favorites.toggle(favorite)
            }
        }
    }
}

/// The Favorites destination: the saved places as a two-column poster grid, built
/// from the same tile as the library and add-on grids.
///
/// A favourite remembers the artwork of the place it was saved from, so the grid
/// has posters; one saved before artwork was recorded shows the placeholder.
struct FavoritesScreen: View {
    @ObservedObject var model: AppModel
    let onOpenDrawer: () -> Void
    let onOpen: (Favorite) -> Void

    @EnvironmentObject private var favorites: FavoriteStore

    var body: some View {
        Group {
            if favorites.items.isEmpty {
                Text("Nothing saved yet. Long-press a folder inside a video add-on to save it here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12),
                        ],
                        spacing: 16
                    ) {
                        ForEach(favorites.items) { favorite in
                            Button { onOpen(favorite) } label: { tile(favorite) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Remove favorite", role: .destructive) {
                                        favorites.remove(favorite)
                                    }
                                }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { onOpenDrawer() } label: { Image(systemName: "line.3.horizontal") }
                    .accessibilityLabel("Open menu")
            }
        }
        .themedScreen()
    }

    private func tile(_ favorite: Favorite) -> some View {
        PosterTile(url: favorite.artworkURL(host: model.host),
                   title: favorite.title,
                   detail: Self.detailLine(for: favorite.target),
                   username: model.host.username,
                   password: model.password)
    }

    /// What kind of place this favourite points at, for the tile's second line.
    static func detailLine(for target: FavoriteTarget) -> String {
        switch target {
        case .section(let raw): return LibrarySection(rawValue: raw)?.title ?? "Library"
        case .episodes: return "Episodes"
        case .albumsOfArtist: return "Albums"
        case .directory(let path): return path.hasPrefix("plugin://") ? "Add-on" : "Folder"
        }
    }
}

/// Episodes of a show, or albums of an artist.
struct ChildrenView: View {
    @ObservedObject var model: AppModel
    let request: ChildrenRequest
    let heading: String
    var onOpenDrawer: (() -> Void)? = nil

    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        List {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Button {
                    Task {
                        if let payload = item.playableItem { await model.play(item: payload) }
                    }
                } label: {
                    MediaRow(item: item, username: model.host.username, password: model.password)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .overlay {
            if items.isEmpty {
                if isLoading {
                    ProgressView()
                } else {
                    Text(error ?? "Nothing to show.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(request.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onOpenDrawer {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { onOpenDrawer() } label: { Image(systemName: "line.3.horizontal") }
                        .accessibilityLabel("Open menu")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                FavoriteButton(title: heading, target: request.favoriteTarget)
            }
        }
        .themedScreen()
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await model.children(of: request)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The Files destination: the media centre's configured sources, each opening a
/// folder browser. This is where a directory becomes reachable, and so where one
/// becomes worth favouriting.
struct FilesScreen: View {
    @ObservedObject var model: AppModel
    let onOpenDrawer: () -> Void

    @State private var sources: [MediaItem] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        List {
            ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                NavigationLink {
                    DirectoryView(model: model, path: source.file, title: source.heading,
                                  onOpenDrawer: onOpenDrawer)
                } label: {
                    MediaRow(item: source, username: model.host.username, password: model.password, showsChevron: true)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if sources.isEmpty {
                if isLoading {
                    ProgressView()
                } else {
                    Text(error ?? "No sources configured on this host.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
        }
        .navigationTitle("Files")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { onOpenDrawer() } label: { Image(systemName: "line.3.horizontal") }
                    .accessibilityLabel("Open menu")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh")
            }
        }
        .themedScreen()
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            sources = try await model.sources(media: "files")
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// One folder on the media centre. Folders drill down; anything else plays.
///
/// Shared by the Files browser and by add-on content. Which layout it uses is
/// derived from the path rather than passed in, so no caller has to remember to
/// say which it is — and a favourite opened on a plugin folder reopens the way it
/// was saved.
struct DirectoryView: View {
    @ObservedObject var model: AppModel
    let path: String
    let title: String
    var onOpenDrawer: (() -> Void)? = nil

    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var error: String?

    /// Add-on content browses as a poster grid, matching the library; a
    /// filesystem folder — the Files browser — stays a list.
    static func layout(forPath path: String) -> LibraryLayout {
        path.hasPrefix("plugin://") ? .grid : .list
    }

    var body: some View {
        Group {
            switch Self.layout(forPath: path) {
            case .list: list
            case .grid: grid
            }
        }
        .overlay { emptyState }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onOpenDrawer {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { onOpenDrawer() } label: { Image(systemName: "line.3.horizontal") }
                        .accessibilityLabel("Open menu")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                FavoriteButton(title: title, target: .directory(path: path))
            }
        }
        .themedScreen()
        .task { await load() }
    }

    private var list: some View {
        List {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                if item.isDirectory {
                    NavigationLink {
                        DirectoryView(model: model, path: item.file, title: item.heading,
                                      onOpenDrawer: onOpenDrawer)
                    } label: {
                        MediaRow(item: item, username: model.host.username, password: model.password, showsChevron: true)
                    }
                    .contextMenu { FavoriteMenuItem(favorite: Favorite(directoryEntry: item)) }
                } else {
                    Button {
                        Task {
                            if let payload = item.playableItem { await model.play(item: payload) }
                        }
                    } label: {
                        MediaRow(item: item, username: model.host.username, password: model.password)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ],
                spacing: 16
            ) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    if item.isDirectory {
                        NavigationLink {
                            DirectoryView(model: model, path: item.file, title: item.heading,
                                          onOpenDrawer: onOpenDrawer)
                        } label: {
                            tile(item)
                        }
                        .contextMenu { FavoriteMenuItem(favorite: Favorite(directoryEntry: item)) }
                    } else {
                        Button {
                            Task {
                                if let payload = item.playableItem { await model.play(item: payload) }
                            }
                        } label: {
                            tile(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if items.isEmpty {
            if isLoading {
                ProgressView()
            } else {
                Text(error ?? "This folder is empty.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
    }

    /// Add-on artwork needs the host's image endpoint — see `Artwork.url(_:host:)`.
    private func tile(_ item: MediaItem) -> some View {
        PosterTile(url: Artwork.poster(for: item.art, thumbnail: item.thumbnail, host: model.host),
                   title: item.heading,
                   detail: item.detailLine,
                   username: model.host.username,
                   password: model.password)
    }

    private func load() async {
        guard !path.isEmpty else {
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await model.directory(path, media: "files")
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
