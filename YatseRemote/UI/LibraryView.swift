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
                ChildrenView(model: model, request: child, heading: item.heading)
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
                ChildrenView(model: model, request: child, heading: item.heading)
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
struct PosterTile: View {
    let item: MediaItem
    let username: String
    let password: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterImage(
                url: Artwork.poster(for: item.art, thumbnail: item.thumbnail),
                username: username,
                password: password
            )
            Text(item.heading)
                .font(.subheadline)
                .lineLimit(2)
                .foregroundStyle(.primary)
            if !item.detailLine.isEmpty {
                Text(item.detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Episodes of a show, or albums of an artist.
struct ChildrenView: View {
    @ObservedObject var model: AppModel
    let request: ChildrenRequest
    let heading: String

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
                    DirectoryView(model: model, path: source.file, title: source.heading)
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
struct DirectoryView: View {
    @ObservedObject var model: AppModel
    let path: String
    let title: String

    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        List {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                if item.isDirectory {
                    NavigationLink {
                        DirectoryView(model: model, path: item.file, title: item.heading)
                    } label: {
                        MediaRow(item: item, username: model.host.username, password: model.password, showsChevron: true)
                    }
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
        .overlay {
            if items.isEmpty {
                if isLoading {
                    ProgressView()
                } else {
                    Text(error ?? "This folder is empty.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                FavoriteButton(title: title, target: .directory(path: path))
            }
        }
        .themedScreen()
        .task { await load() }
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
