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

    @State private var destination: ShellDestination = .remote
    @State private var drawerOpen = false

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
                    MiniPlayer(model: model) { select(.remote) }
                }
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
