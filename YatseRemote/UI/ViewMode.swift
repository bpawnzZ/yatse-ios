import SwiftUI

/// How a browsable screen lays its items out.
///
/// One setting for the whole app rather than one per screen: the drawer's
/// sections are a single kind of screen, and a memory per screen would mean
/// re-picking the layout every time another one is opened.
///
/// The case order is the order of the menu.
enum ViewMode: String, CaseIterable, Identifiable {
    case grid
    case compact
    case dense
    case list

    var id: String { rawValue }

    /// The `UserDefaults` key the setting lives under. Named here so the control
    /// that writes it and the screens that read it cannot drift apart.
    static let storageKey = "viewMode"

    /// What a fresh install opens as: the two-column poster grid.
    static let fallback = ViewMode.grid

    /// How many tiles fit across, or 1 for the list.
    var columnCount: Int {
        switch self {
        case .grid: return 2
        case .compact: return 3
        case .dense: return 4
        case .list: return 1
        }
    }

    var isGrid: Bool { self != .list }

    var title: String {
        switch self {
        case .grid: return "2-wide grid"
        case .compact: return "3-wide grid"
        case .dense: return "4-wide grid"
        case .list: return "List"
        }
    }

    /// Distinct per mode so the menu says which is which at a glance. `ViewModeTests`
    /// checks each one resolves, because a symbol that does not exist renders as
    /// nothing at all — the blank-icon failure this project has already shipped once.
    var systemImage: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .compact: return "square.grid.3x3"
        case .dense: return "square.grid.3x3.fill"
        case .list: return "list.bullet"
        }
    }

    /// The columns every grid branch renders. Defined once, so "3-wide" cannot
    /// mean different spacing on two screens.
    var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: columnCount)
    }

    /// A tile's text has to shrink with the tile: at four columns a `.subheadline`
    /// title has no room to wrap.
    var usesSmallTileText: Bool { columnCount >= 3 }

    /// The densest grid drops the second line of a tile rather than rendering it
    /// at a size nobody can read.
    var showsTileDetail: Bool { columnCount < 4 }
}

/// The toolbar control that switches the layout. Reads and writes the same key
/// the screens read, so one setting follows the user everywhere; the current
/// mode is the one marked in the menu.
struct ViewModeMenu: View {
    @AppStorage(ViewMode.storageKey) private var mode = ViewMode.fallback

    var body: some View {
        Menu {
            ForEach(ViewMode.allCases) { option in
                Button {
                    mode = option
                } label: {
                    Label(option.title,
                          systemImage: option == mode ? "checkmark" : option.systemImage)
                }
            }
        } label: {
            Image(systemName: mode.systemImage)
        }
        .accessibilityLabel("Layout")
    }
}
