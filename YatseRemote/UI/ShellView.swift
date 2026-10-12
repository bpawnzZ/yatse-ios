import SwiftUI

/// The host-centric shell: one navigation stack for the current destination,
/// the slide-over drawer above it, and the mini-player pinned to the bottom.
///
/// The destination is selected by value rather than pushed, because drawer
/// destinations are top-level — back must not cross the drawer boundary. Giving
/// the stack an identity of `destination` rebuilds it when the destination
/// changes, and `NavigationMemory` is what decides what it is rebuilt *with*:
/// the place that destination was last left at, rather than nothing. Favourites
/// that are *places inside* a destination (a show's episodes, a folder) are
/// pushed onto this stack instead.
struct ShellView: View {
    @EnvironmentObject private var session: Session
    @Environment(\.scenePhase) private var scenePhase

    @State private var destination: ShellDestination = .remote
    @State private var drawerOpen = false
    @State private var showingNowPlaying = false
    @State private var pushed: [Favorite] = []
    @State private var memory = NavigationMemory()

    var body: some View {
        if let model = session.model {
            shell(model)
        } else {
            Color.clear
        }
    }

    private func shell(_ model: AppModel) -> some View {
        ZStack(alignment: .leading) {
            NavigationStack(path: $pushed) {
                destinationView(model)
                    .navigationDestination(for: Favorite.self) { favorite in
                        favoriteDestination(model, favorite)
                    }
            }
            .id(destination)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PlaybackBar(model: model) { showingNowPlaying = true }
            }

            if drawerOpen {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { closeDrawer() }
                    .accessibilityLabel("Close menu")

                AppDrawer(selected: destination, onSelect: select)
                .ignoresSafeArea(edges: .vertical)
                .transition(.move(edge: .leading))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: drawerOpen)
        .onChange(of: scenePhase) { _, phase in
            // Returning to the foreground, what is playing must be re-queried
            // rather than inferred from state that froze while suspended.
            guard phase == .active else { return }
            Task { await model.refresh() }
        }
        .fullScreenCover(isPresented: $showingNowPlaying) {
            NowPlayingView(model: model)
        }
    }

    @ViewBuilder
    private func destinationView(_ model: AppModel) -> some View {
        switch destination {
        case .remote:
            RemoteScreen(model: model, onOpenDrawer: openDrawer, onSelect: select)
        case .home:
            HomeScreen(model: model, onOpenDrawer: openDrawer, onSelect: select)
        case .movies, .tvShows, .music:
            LibraryView(model: model, section: destination.librarySection ?? .movies, onOpenDrawer: openDrawer)
        case .files:
            FilesScreen(model: model, onOpenDrawer: openDrawer)
        case .addons:
            AddonsScreen(model: model, onOpenDrawer: openDrawer)
        case .favorites:
            FavoritesScreen(model: model, onOpenDrawer: openDrawer, onOpen: { open(model, $0) })
        case .settings:
            SettingsView(onOpenDrawer: openDrawer)
        case .about:
            AboutScreen(onOpenDrawer: openDrawer)
        case .pvr:
            PlaceholderScreen(destination: destination, onOpenDrawer: openDrawer)
        }
    }

    /// A favourite either switches destination — a library section is a
    /// destination, not a pushed screen — or pushes the screen that reproduces
    /// the place it was saved from.
    private func open(_ model: AppModel, _ favorite: Favorite) {
        switch favorite.target {
        case .section(let raw):
            if let section = LibrarySection(rawValue: raw),
               let match = ShellDestination.allCases.first(where: { $0.librarySection == section }) {
                select(match)
            } else {
                withAnimation { drawerOpen = false }
            }
        case .episodes, .albumsOfArtist, .directory:
            pushed = [favorite]
            // The favourite's place is now where this destination is, so coming
            // back to it lands here rather than on something already left.
            memory.record(pushed, for: destination)
            withAnimation { drawerOpen = false }
        }
    }

    @ViewBuilder
    private func favoriteDestination(_ model: AppModel, _ favorite: Favorite) -> some View {
        switch favorite.target {
        case .episodes(let tvshowID):
            ChildrenView(model: model,
                         request: .episodes(tvshowID: tvshowID),
                         heading: favorite.title,
                         onOpenDrawer: openDrawer)
        case .albumsOfArtist(let artistID):
            ChildrenView(model: model,
                         request: .albumsOfArtist(artistID: artistID),
                         heading: favorite.title,
                         onOpenDrawer: openDrawer)
        case .directory(let directory):
            DirectoryView(model: model, path: directory, title: favorite.title,
                          onOpenDrawer: openDrawer)
        case .section:
            // A section switches destination; there is nothing to push.
            EmptyView()
        }
    }

    private func openDrawer() { withAnimation { drawerOpen = true } }
    private func closeDrawer() { withAnimation { drawerOpen = false } }

    /// Selecting a destination remembers where it was left and restores the place
    /// previously reached in the one being opened, rather than clearing the path.
    /// Re-selecting the destination already shown returns it to its own root.
    private func select(_ item: ShellDestination) {
        if item == destination {
            pushed = []
            memory.record([], for: item)
        } else {
            memory.record(pushed, for: destination)
            pushed = memory.path(for: item)
            destination = item
        }
        withAnimation { drawerOpen = false }
    }
}

/// The bar observes the model itself, and that is the whole point of it being a
/// separate view.
///
/// `safeAreaInset`'s closure is evaluated by whoever owns it, and `ShellView`
/// never observes `AppModel` — it takes the model as a parameter and only reads
/// `session`. Reading `activePlayer` inside that closure therefore never
/// invalidated the shell, so the bar did not appear when playback started: it
/// only showed up once something else rebuilt the shell, such as navigating to
/// another destination and back. Owning `@ObservedObject` here fixes the
/// invalidation at its source rather than papering over it.
///
/// The bar is removed from the tree when nothing plays, so the inset collapses
/// to nothing and the remote keeps the space.
private struct PlaybackBar: View {
    @ObservedObject var model: AppModel
    let onOpen: () -> Void

    private var isVisible: Bool { MiniPlayer.isVisible(activePlayer: model.activePlayer) }

    var body: some View {
        Group {
            if isVisible {
                MiniPlayer(model: model, onOpen: onOpen)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isVisible)
    }
}

/// Remembers, per destination, the screens pushed within it, so leaving a
/// destination and coming back restores the place instead of resetting to the
/// root.
///
/// Pure and unit-tested, because the rule is invisible: a destination never
/// visited, one sitting at its root, and one holding a place all have to answer
/// differently. Session-scoped — nothing is persisted, so a relaunch starts every
/// destination at its own root rather than reopening somewhere from a previous
/// run. A destination that ended at its root forgets its place, so "back to the
/// top" means the top.
struct NavigationMemory {
    private var paths: [ShellDestination: [Favorite]] = [:]

    func path(for destination: ShellDestination) -> [Favorite] {
        paths[destination] ?? []
    }

    mutating func record(_ path: [Favorite], for destination: ShellDestination) {
        paths[destination] = path.isEmpty ? nil : path
    }
}
