import SwiftUI

/// The host-centric shell: one navigation stack for the current destination,
/// the slide-over drawer above it, and the mini-player pinned to the bottom.
///
/// The destination is selected by value rather than pushed, because drawer
/// destinations are top-level — back must not cross the drawer boundary. Giving
/// the stack an identity of `destination` clears any pushed detail screens when
/// the destination changes.
struct ShellView: View {
    @EnvironmentObject private var session: Session
    @Environment(\.scenePhase) private var scenePhase

    @State private var destination: ShellDestination = .remote
    @State private var drawerOpen = false
    @State private var showingNowPlaying = false

    var body: some View {
        if let model = session.model {
            shell(model)
        } else {
            Color.clear
        }
    }

    private func shell(_ model: AppModel) -> some View {
        ZStack(alignment: .leading) {
            NavigationStack {
                destinationView(model)
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
        case .settings:
            SettingsView(onOpenDrawer: openDrawer)
        case .about:
            AboutScreen(onOpenDrawer: openDrawer)
        case .pvr, .files, .addons:
            PlaceholderScreen(destination: destination, onOpenDrawer: openDrawer)
        }
    }

    private func openDrawer() { withAnimation { drawerOpen = true } }
    private func closeDrawer() { withAnimation { drawerOpen = false } }

    private func select(_ item: ShellDestination) {
        destination = item
        withAnimation { drawerOpen = false }
    }
}
