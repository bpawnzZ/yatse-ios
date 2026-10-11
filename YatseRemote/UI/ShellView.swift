import SwiftUI

/// The host-centric shell: one navigation stack for the current destination,
/// the slide-over drawer above it, and the mini-player pinned to the bottom.
///
/// The destination is selected by value rather than pushed, because drawer
/// destinations are top-level — back must not cross the drawer boundary. Giving
/// the stack an identity of `destination` clears any pushed detail screens when
/// the destination changes. Favourites that are *places inside* a destination
/// (a show's episodes, a folder) are pushed onto this stack instead.
struct ShellView: View {
    @EnvironmentObject private var session: Session
    @Environment(\.scenePhase) private var scenePhase

    @State private var destination: ShellDestination = .remote
    @State private var drawerOpen = false
    @State private var showingNowPlaying = false
    @State private var pushed: [Favorite] = []

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
                if MiniPlayer.isVisible(activePlayer: model.activePlayer) {
                    // Removed from the tree when nothing plays, so the inset
                    // collapses to nothing and the remote keeps the space.
                    MiniPlayer(model: model) { showingNowPlaying = true }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.22),
                       value: MiniPlayer.isVisible(activePlayer: model.activePlayer))

            if drawerOpen {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { closeDrawer() }
                    .accessibilityLabel("Close menu")

                AppDrawer(
                    selected: destination,
                    onSelect: select,
                    onOpenFavorite: { open(model, $0) }
                )
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
            withAnimation { drawerOpen = false }
        }
    }

    @ViewBuilder
    private func favoriteDestination(_ model: AppModel, _ favorite: Favorite) -> some View {
        switch favorite.target {
        case .episodes(let tvshowID):
            ChildrenView(model: model,
                         request: .episodes(tvshowID: tvshowID),
                         heading: favorite.title)
        case .albumsOfArtist(let artistID):
            ChildrenView(model: model,
                         request: .albumsOfArtist(artistID: artistID),
                         heading: favorite.title)
        case .directory(let directory):
            DirectoryView(model: model, path: directory, title: favorite.title)
        case .section:
            // A section switches destination; there is nothing to push.
            EmptyView()
        }
    }

    private func openDrawer() { withAnimation { drawerOpen = true } }
    private func closeDrawer() { withAnimation { drawerOpen = false } }

    private func select(_ item: ShellDestination) {
        pushed.removeAll()
        destination = item
        withAnimation { drawerOpen = false }
    }
}
