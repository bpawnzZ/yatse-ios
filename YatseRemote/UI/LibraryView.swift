import SwiftUI

/// Browses one library section. Poster media (Movies, TV Shows) is a two-column
/// grid of poster tiles; media read as text (Artists, Albums) stays a list. The
/// two share pagination, refresh and the empty/error state, so there is still
/// one browser — only the layout differs.
struct LibraryView: View {
    @ObservedObject var model: AppModel
    let section: LibrarySection
    var onOpenDrawer: (() -> Void)? = nil

    @Environment(\.scrollMemory) private var scrollMemory
    /// The layout every browse screen shares — see `ViewMode`.
    @AppStorage(ViewMode.storageKey) private var mode = ViewMode.fallback

    @State private var items: [MediaItem] = []
    @State private var total = 0
    @State private var isLoading = false
    @State private var error: String?
    /// The item the view was left at, held until the content is back and it can
    /// be scrolled to.
    @State private var topItem: Int?

    private let pageSize = 60

    private var scrollKey: String { ScrollPlace.library(section) }

    var body: some View {
        Group {
            if mode.isGrid { grid } else { list }
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
                ViewModeMenu()
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh")
            }
        }
        .themedScreen()
        .task { await restoreAndReload() }
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
        .rememberedScrollPosition(scrollKey, top: $topItem)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: mode.gridColumns, spacing: 16) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    gridCell(for: item)
                        .onAppear { loadMoreIfNeeded(index) }
                }

                if isLoading && !items.isEmpty {
                    ProgressView().gridCellColumns(mode.columnCount)
                }
            }
            .scrollTargetLayout()
            .padding()
        }
        .rememberedScrollPosition(scrollKey, top: $topItem)
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
            // Value-based, not the destination-closure form: only values land in
            // `ShellView.pushed`, and a destination change rebuilds the stack
            // (`.id(destination)`) so a closure-built screen is discarded without
            // the shell ever knowing it existed.
            NavigationLink(value: favorite(for: item, target: child.favoriteTarget)) {
                MediaRow(item: item, username: model.host.username, password: model.password, showsChevron: true)
            }
            .contextMenu { FavoriteMenuItem(favorite: favorite(for: item, target: child.favoriteTarget)) }
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
            NavigationLink(value: favorite(for: item, target: child.favoriteTarget)) {
                PosterTile(item: item, username: model.host.username, password: model.password, mode: mode)
            }
            .contextMenu { FavoriteMenuItem(favorite: favorite(for: item, target: child.favoriteTarget)) }
        } else {
            Button {
                Task { await play(item) }
            } label: {
                PosterTile(item: item, username: model.host.username, password: model.password, mode: mode)
            }
            .buttonStyle(.plain)
        }
    }

    /// The favourite a tile or row stands for. Saving from here is the long
    /// press's job now the toolbar star is gone, and the artwork travels with it
    /// so the Favorites grid shows a poster rather than a placeholder.
    private func favorite(for item: MediaItem, target: FavoriteTarget) -> Favorite {
        Favorite(title: item.heading,
                 target: target,
                 art: item.art,
                 thumbnail: item.thumbnail)
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

    /// Reloads, then puts the view back where it was left.
    ///
    /// The remembered place can sit several pages below the first one, and a grid
    /// cannot scroll to an item it has not loaded, so the pages up to it are
    /// pulled first. Bounded by how many pages that far down and by `total`, so a
    /// section that ends early cannot spin here.
    private func restoreAndReload() async {
        let remembered = scrollMemory.top(for: scrollKey)
        await reload()
        guard let remembered else { return }
        for _ in 0..<(remembered / pageSize + 1) where items.count <= remembered && items.count < total {
            await loadMore()
        }
        topItem = remembered
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
    /// The tile is sized by the layout it is rendered in, so it has to know it —
    /// and the parameter deliberately has no default, because a call site that
    /// forgets it would silently render full-size tiles in a dense grid.
    let mode: ViewMode

    init(url: URL?, title: String, detail: String, username: String, password: String, mode: ViewMode) {
        self.url = url
        self.title = title
        self.detail = detail
        self.username = username
        self.password = password
        self.mode = mode
    }

    /// The library grid's tile: artwork and text come from the item.
    init(item: MediaItem, username: String, password: String, mode: ViewMode) {
        self.init(url: Artwork.poster(for: item.art, thumbnail: item.thumbnail),
                  title: item.heading,
                  detail: item.detailLine,
                  username: username,
                  password: password,
                  mode: mode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterImage(url: url, username: username, password: password)
            Text(title)
                .font(mode.usesSmallTileText ? .caption : .subheadline)
                .lineLimit(2)
                .foregroundStyle(.primary)
            if !detail.isEmpty && mode.showsTileDetail {
                Text(detail)
                    .font(mode.usesSmallTileText ? .caption2 : .caption)
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
    @Environment(\.scrollMemory) private var scrollMemory
    /// The layout every browse screen shares — see `ViewMode`.
    @AppStorage(ViewMode.storageKey) private var mode = ViewMode.fallback
    @State private var topItem: Int?

    var body: some View {
        Group {
            if favorites.items.isEmpty {
                // The only place that teaches the gesture, now the toolbar star is
                // gone: saving a place is a long press on it.
                Text("Nothing saved yet. Long-press a folder, a show or an artist to save it here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            } else if mode.isGrid {
                grid
            } else {
                list
            }
        }
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { onOpenDrawer() } label: { Image(systemName: "line.3.horizontal") }
                    .accessibilityLabel("Open menu")
            }
            ToolbarItem(placement: .primaryAction) { ViewModeMenu() }
        }
        .themedScreen()
        // The grid is drawn from the store, so the content is there on the first
        // pass; restoring in a task puts it back after that pass, not before it.
        .task { topItem = scrollMemory.top(for: ScrollPlace.favorites) }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: mode.gridColumns, spacing: 16) {
                ForEach(favorites.items) { favorite in
                    Button { onOpen(favorite) } label: { tile(favorite) }
                        .buttonStyle(.plain)
                        .contextMenu { removeMenu(favorite) }
                }
            }
            .scrollTargetLayout()
            .padding()
        }
        .rememberedScrollPosition(ScrollPlace.favorites, top: $topItem)
    }

    private var list: some View {
        List {
            ForEach(favorites.items) { favorite in
                Button { onOpen(favorite) } label: {
                    FavoriteRow(favorite: favorite,
                                artURL: favorite.artworkURL(host: model.host),
                                username: model.host.username,
                                password: model.password)
                }
                .buttonStyle(.plain)
                .contextMenu { removeMenu(favorite) }
            }
        }
        .listStyle(.plain)
        .rememberedScrollPosition(ScrollPlace.favorites, top: $topItem)
    }

    private func removeMenu(_ favorite: Favorite) -> some View {
        Button("Remove favorite", role: .destructive) { favorites.remove(favorite) }
    }

    private func tile(_ favorite: Favorite) -> some View {
        PosterTile(url: favorite.artworkURL(host: model.host),
                   title: favorite.title,
                   detail: Self.detailLine(for: favorite.target),
                   username: model.host.username,
                   password: model.password,
                   mode: mode)
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
    var onOpenDrawer: (() -> Void)? = nil

    @Environment(\.scrollMemory) private var scrollMemory
    /// The layout every browse screen shares — see `ViewMode`.
    @AppStorage(ViewMode.storageKey) private var mode = ViewMode.fallback

    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var topItem: Int?

    private var scrollKey: String { ScrollPlace.children(request) }

    var body: some View {
        Group {
            if mode.isGrid { grid } else { list }
        }
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
            ToolbarItem(placement: .primaryAction) { ViewModeMenu() }
        }
        .themedScreen()
        .task {
            await load()
            topItem = scrollMemory.top(for: scrollKey)
        }
    }

    private var list: some View {
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
        .rememberedScrollPosition(scrollKey, top: $topItem)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: mode.gridColumns, spacing: 16) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    Button {
                        Task {
                            if let payload = item.playableItem { await model.play(item: payload) }
                        }
                    } label: {
                        PosterTile(item: item,
                                   username: model.host.username,
                                   password: model.password,
                                   mode: mode)
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollTargetLayout()
            .padding()
        }
        .rememberedScrollPosition(scrollKey, top: $topItem)
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

    /// The layout every browse screen shares — see `ViewMode`.
    @AppStorage(ViewMode.storageKey) private var mode = ViewMode.fallback

    @State private var sources: [MediaItem] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if mode.isGrid { grid } else { list }
        }
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
            ToolbarItemGroup(placement: .primaryAction) {
                ViewModeMenu()
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

    private var list: some View {
        List {
            ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                NavigationLink(value: Favorite(directoryEntry: source)) {
                    MediaRow(item: source, username: model.host.username, password: model.password, showsChevron: true)
                }
                .contextMenu { FavoriteMenuItem(favorite: Favorite(directoryEntry: source)) }
            }
        }
        .listStyle(.plain)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: mode.gridColumns, spacing: 16) {
                ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                    NavigationLink(value: Favorite(directoryEntry: source)) {
                        PosterTile(item: source,
                                   username: model.host.username,
                                   password: model.password,
                                   mode: mode)
                    }
                    .contextMenu { FavoriteMenuItem(favorite: Favorite(directoryEntry: source)) }
                }
            }
            .scrollTargetLayout()
            .padding()
        }
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

    @Environment(\.scrollMemory) private var scrollMemory
    /// The layout every browse screen shares — see `ViewMode`. It used to be
    /// derived from the path, which made the same content a grid or a list
    /// depending on how it was reached.
    @AppStorage(ViewMode.storageKey) private var mode = ViewMode.fallback

    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var topItem: Int?

    private var scrollKey: String { ScrollPlace.directory(path) }

    var body: some View {
        Group {
            if mode.isGrid { grid } else { list }
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
            ToolbarItem(placement: .primaryAction) { ViewModeMenu() }
        }
        .themedScreen()
        .task {
            await load()
            topItem = scrollMemory.top(for: scrollKey)
        }
    }

    private var list: some View {
        List {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                if item.isDirectory {
                    NavigationLink(value: Favorite(directoryEntry: item)) {
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
        .rememberedScrollPosition(scrollKey, top: $topItem)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: mode.gridColumns, spacing: 16) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    if item.isDirectory {
                        NavigationLink(value: Favorite(directoryEntry: item)) {
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
            .scrollTargetLayout()
            .padding()
        }
        .rememberedScrollPosition(scrollKey, top: $topItem)
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
                   password: model.password,
                   mode: mode)
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
