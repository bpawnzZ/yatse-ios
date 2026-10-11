import SwiftUI

/// Every colour the remote draws with, as named tokens. Views read these
/// through `@Environment(\.remoteTheme)` and never hardcode a colour, so the
/// two themes cannot drift apart and a swap repaints everything at once.
struct RemoteTheme: Equatable {
    /// Page background, behind everything and visible once artwork is gone.
    var background: Color
    /// Resting fill for a control tile. Deliberately translucent so artwork
    /// behind the remote reads through it.
    var tileFill: Color
    /// Fill while a tile is held.
    var tileFillPressed: Color
    /// The single non-neutral colour: D-pad chevrons, the touchpad toggle.
    var accent: Color
    /// Icons and text.
    var icon: Color
    /// The flat bar the shortcut row sits on.
    var navBarFill: Color
    /// The hairline along the top of the now-playing bar.
    var divider: Color
    /// The now-playing bar's own translucent panel.
    var barFill: Color
    /// Tint laid over the blurred artwork so icons stay readable without the
    /// artwork being blacked out.
    var artworkScrim: Color
    /// Corner radius shared by every tile.
    var tileCornerRadius: CGFloat
}

extension RemoteTheme {
    /// Saturated blue, the default.
    static let blue = RemoteTheme(
        background: Color(hex: 0x0D5FB8),
        tileFill: Color.white.opacity(0.14),
        tileFillPressed: Color.white.opacity(0.26),
        accent: Color(hex: 0x2F8CFF),
        icon: .white,
        navBarFill: Color(hex: 0x3D86D8).opacity(0.6),
        divider: Color(hex: 0x2F8CFF),
        barFill: Color(hex: 0x0D5FB8).opacity(0.6),
        artworkScrim: Color(hex: 0x0D5FB8).opacity(0.4),
        tileCornerRadius: 18
    )

    /// The original dark remote, kept selectable.
    static let dark = RemoteTheme(
        background: .black,
        tileFill: Color.white.opacity(0.12),
        tileFillPressed: Color.white.opacity(0.24),
        accent: .orange,
        icon: .white,
        navBarFill: .clear,
        divider: Color.white.opacity(0.25),
        barFill: Color(hex: 0x111111).opacity(0.92),
        artworkScrim: Color.black.opacity(0.5),
        tileCornerRadius: 12
    )
}

/// The active theme, persisted so it survives a relaunch.
enum ThemeName: String, CaseIterable, Identifiable {
    case blue
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue: return "Blue"
        case .dark: return "Dark"
        }
    }

    var theme: RemoteTheme {
        switch self {
        case .blue: return .blue
        case .dark: return .dark
        }
    }

    /// Shared by the root injector and the picker in Settings.
    static let storageKey = "remoteTheme"
}

private struct RemoteThemeKey: EnvironmentKey {
    static let defaultValue = RemoteTheme.blue
}

extension EnvironmentValues {
    var remoteTheme: RemoteTheme {
        get { self[RemoteThemeKey.self] }
        set { self[RemoteThemeKey.self] = newValue }
    }
}

/// Injects the selected theme. Applied once at the app root so every screen —
/// including the full-screen now-playing cover — sees the same tokens. The blue
/// theme draws every surface from these tokens, so it looks the same whatever
/// the system's light/dark setting is.
private struct ThemedRoot: ViewModifier {
    @AppStorage(ThemeName.storageKey) private var theme: ThemeName = .blue

    func body(content: Content) -> some View {
        content.environment(\.remoteTheme, theme.theme)
    }
}

extension View {
    func themedRoot() -> some View { modifier(ThemedRoot()) }
}

/// A tile that lightens while held. The theme is passed in rather than read
/// from the environment because a `ButtonStyle` is not a `View`.
struct ThemeTileButtonStyle: ButtonStyle {
    let theme: RemoteTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? theme.tileFillPressed : theme.tileFill,
                in: RoundedRectangle(cornerRadius: theme.tileCornerRadius, style: .continuous)
            )
    }
}

private extension Color {
    /// The tokens above are specified as hex, so the palette stays one readable
    /// block instead of a wall of `Color(red:green:blue:)`.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
