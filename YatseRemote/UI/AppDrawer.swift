import SwiftUI

/// A top-level destination in the shell.
///
/// This is the single source of truth for what a destination is called and what
/// icon it uses — the drawer and the Remote's shortcut strip both read it, so
/// the two cannot drift apart.
enum ShellDestination: String, CaseIterable, Identifiable {
    case home
    case movies
    case tvShows
    case music
    case pvr
    case files
    case addons
    case favorites
    case remote
    case settings
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .movies: return "Movies"
        case .tvShows: return "TV Shows"
        case .music: return "Music"
        case .pvr: return "Pvr"
        case .files: return "Files"
        case .addons: return "Addons"
        case .favorites: return "Favorites"
        case .remote: return "Remote"
        case .settings: return "Settings"
        case .about: return "About / Help"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .movies: return "movieclapper"
        case .tvShows: return "tv"
        case .music: return "headphones"
        case .pvr: return "dot.radiowaves.left.and.right"
        case .files: return "folder"
        case .addons: return "puzzlepiece.extension"
        case .favorites: return "star"
        case .remote: return "av.remote"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        }
    }

    /// Whether a screen exists for this destination. Unimplemented ones render a
    /// placeholder rather than a dead end.
    var isImplemented: Bool {
        switch self {
        case .home, .movies, .tvShows, .music, .remote, .settings, .about,
             .addons, .files, .favorites:
            return true
        case .pvr:
            return false
        }
    }

    /// The library section this destination opens, if it is a library section.
    var librarySection: LibrarySection? {
        switch self {
        case .movies: return .movies
        case .tvShows: return .tvshows
        case .music: return .artists
        default: return nil
        }
    }

    /// Destinations listed above the drawer divider, in Yatse's order.
    static let destinations: [ShellDestination] =
        [.home, .movies, .tvShows, .music, .pvr, .files, .addons, .favorites, .remote]

    /// Destinations listed below the divider.
    static let secondary: [ShellDestination] = [.settings, .about]
}

/// The five quick links shown under the Remote's app bar. Three are in-app
/// destinations and take their name and icon from them; Home and Pictures drive
/// the host instead. Delegating here is what keeps this row and the drawer from
/// showing different icons for the same thing — including Home, whose tile drives
/// the host but still wears the drawer Home row's word and mark.
enum RemoteShortcut: String, CaseIterable, Identifiable {
    case home
    case movies
    case tvShows
    case music
    case pictures

    var id: String { rawValue }

    var title: String {
        if let destination { return destination.title }
        return self == .home ? ShellDestination.home.title : "Pictures"
    }

    var systemImage: String {
        if let destination { return destination.systemImage }
        return self == .home ? ShellDestination.home.systemImage : "photo.stack"
    }

    /// The shell destination this shortcut switches the app to, or nil when the
    /// tile drives the host instead.
    ///
    /// Home is nil on purpose. The drawer's Home row switches this app's screen;
    /// the Remote's Home tile sends the host's own Home — where its Home button
    /// and backing out of a library both land — because one tile in a row of host
    /// controls should not be the only one that never reaches the host.
    var destination: ShellDestination? {
        switch self {
        case .home, .pictures: return nil
        case .movies: return .movies
        case .tvShows: return .tvShows
        case .music: return .music
        }
    }
}

/// The slide-over navigation drawer: host header with a switcher and keyboard /
/// mic / search actions, the destination list, then Settings and About.
///
/// Saved favourites are a destination of their own rather than one row each —
/// a 300pt drawer cannot hold their poster grid, and one row per favourite
/// grows without bound.
struct AppDrawer: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var store: HostStore
    @Environment(\.remoteTheme) private var theme

    let selected: ShellDestination
    let onSelect: (ShellDestination) -> Void

    @State private var showingKeyboard = false
    @State private var showingSearch = false
    @State private var showingMic = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(ShellDestination.destinations) { item in
                        itemRow(item)
                    }

                    Divider().padding(.vertical, 8)
                    ForEach(ShellDestination.secondary) { item in
                        itemRow(item)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.surface)
        .sheet(isPresented: $showingKeyboard) {
            if let model = session.model { TextEntrySheet(model: model) }
        }
        .sheet(isPresented: $showingSearch) {
            PlaceholderSheet(title: "Search", message: "Library search is not available in this build.")
        }
        .sheet(isPresented: $showingMic) {
            PlaceholderSheet(title: "Voice input", message: "Voice input is not available in this build.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(theme.accent.opacity(0.25))
                    .overlay(Image(systemName: "play.circle.fill").foregroundStyle(theme.accent))
                    .frame(width: 44, height: 44)
                Spacer()
                headerButton("keyboard") { showingKeyboard = true }
                headerButton("mic") { showingMic = true }
                headerButton("magnifyingglass") { showingSearch = true }
            }
            hostSwitcher
        }
        .padding(16)
    }

    private func headerButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(theme.tileFill, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol)
    }

    private var hostSwitcher: some View {
        Menu {
            ForEach(store.hosts) { host in
                Button {
                    session.activate(host: host, password: store.password(for: host))
                } label: {
                    if host.id == session.host?.id {
                        Label(host.displayName, systemImage: "checkmark")
                    } else {
                        Text(host.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(session.host?.displayName ?? "No host")
                    .font(.headline)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
            }
        }
    }

    private func itemRow(_ item: ShellDestination) -> some View {
        row(symbol: item.systemImage,
            title: item.title,
            isSelected: item == selected) {
            onSelect(item)
        }
    }

    private func row(symbol: String,
                     title: String,
                     isSelected: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbol)
                    .frame(width: 24)
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? theme.accent.opacity(0.18) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? theme.accent : theme.icon)
    }
}
