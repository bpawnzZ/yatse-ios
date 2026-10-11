import SwiftUI

/// A top-level destination in the shell.
///
/// This is the single source of truth for what a destination is called, what
/// icon it uses, and whether a screen exists for it — the drawer and the
/// Remote's shortcut strip both read it, so the two cannot drift apart.
enum ShellDestination: String, CaseIterable, Identifiable {
    case home
    case movies
    case tvShows
    case music
    case pvr
    case files
    case addons
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
        case .remote: return "Remote"
        case .settings: return "Settings"
        case .about: return "About / Help"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .movies: return "film"
        case .tvShows: return "tv"
        case .music: return "music.note"
        case .pvr: return "dot.radiowaves.left.and.right"
        case .files: return "folder"
        case .addons: return "puzzlepiece.extension"
        case .remote: return "av.remote"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        }
    }

    /// Whether a screen exists for this destination. Unimplemented ones render a
    /// placeholder rather than a dead end.
    var isImplemented: Bool {
        switch self {
        case .home, .movies, .tvShows, .music, .remote, .settings, .about: return true
        case .pvr, .files, .addons: return false
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
        [.home, .movies, .tvShows, .music, .pvr, .files, .addons, .remote]

    /// Destinations listed below the divider.
    static let secondary: [ShellDestination] = [.settings, .about]
}

/// The five quick links shown under the Remote's app bar. Four are destinations;
/// Pictures is a Kodi window command, so it has no shell destination.
enum RemoteShortcut: String, CaseIterable, Identifiable {
    case home
    case movies
    case tvShows
    case music
    case pictures

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .movies: return "Movies"
        case .tvShows: return "TV Shows"
        case .music: return "Music"
        case .pictures: return "Pictures"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .movies: return "clapperboard"
        case .tvShows: return "tv"
        case .music: return "headphones"
        case .pictures: return "photo.stack"
        }
    }

    /// The shell destination this shortcut jumps to, or nil when it is a Kodi
    /// window rather than an in-app destination.
    var destination: ShellDestination? {
        switch self {
        case .home: return .home
        case .movies: return .movies
        case .tvShows: return .tvShows
        case .music: return .music
        case .pictures: return nil
        }
    }
}

/// The slide-over navigation drawer: host header with a switcher and keyboard /
/// mic / search actions, the destination list, then Settings and About.
struct AppDrawer: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var store: HostStore

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
        .background(.regularMaterial)
        .sheet(isPresented: $showingKeyboard) {
            if let model = session.model { TextEntrySheet(model: model) }
        }
        .sheet(isPresented: $showingSearch) {
            PlaceholderSheet(title: "Search", message: "Library search arrives with the library screens.")
        }
        .sheet(isPresented: $showingMic) {
            PlaceholderSheet(title: "Voice input", message: "Voice input is not available in this build.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(.tint.opacity(0.25))
                    .overlay(Image(systemName: "play.circle.fill").foregroundStyle(.tint))
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
                .background(.quaternary, in: Circle())
        }
        .buttonStyle(.plain)
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
        Button {
            onSelect(item)
        } label: {
            HStack(spacing: 16) {
                Image(systemName: item.systemImage)
                    .frame(width: 24)
                Text(item.title)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(item == selected ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(item == selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
    }
}
