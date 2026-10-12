import SwiftUI

/// A key the Remote issues in touchpad mode.
enum TouchKey: String {
    case up, down, left, right, select
}

/// Turns a swipe on the touch surface into a key. Pure and static so the mapping
/// can be unit-tested without a host: the dominant axis wins, and a movement
/// below the threshold — a tap — is left to the caller's tap handler.
enum TouchpadGestureResolver {
    /// Drag distance below which a gesture is a tap. Shared with the surface so
    /// the two cannot disagree and leave a dead zone.
    static let threshold: CGFloat = 24

    static func key(forTranslation translation: CGSize, threshold: CGFloat = 24) -> TouchKey? {
        let dx = translation.width
        let dy = translation.height
        guard abs(dx) >= threshold || abs(dy) >= threshold else { return nil }
        if abs(dx) >= abs(dy) { return dx >= 0 ? .right : .left }
        return dy >= 0 ? .down : .up
    }

    /// What one finished touch means: a swipe key, or `select` when the finger
    /// barely moved.
    ///
    /// A tap and a swipe are the same recogniser reporting two different
    /// translations, rather than a drag and a tap competing over one surface —
    /// where the drag only exists once the finger has already travelled
    /// `threshold` points, leaving the touch to be resolved as a tap on release.
    /// `TouchpadSurface` sends whatever this returns.
    static func action(forTranslation translation: CGSize, threshold: CGFloat = 24) -> TouchKey {
        key(forTranslation: translation, threshold: threshold) ?? .select
    }
}

/// The touch surface shown in place of the directional pad in touchpad mode.
struct TouchpadSurface: View {
    @ObservedObject var model: AppModel

    @Environment(\.remoteTheme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: theme.tileCornerRadius, style: .continuous)
            .fill(theme.tileFill)
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "hand.tap")
                        .font(.largeTitle)
                    Text("Swipe to move, tap to select")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: theme.tileCornerRadius, style: .continuous))
            // One gesture, not a drag plus a tap. `minimumDistance: 0` claims the
            // touch as it lands, which is right for a surface with nothing
            // underneath to scroll, and the total translation at release decides
            // swipe or tap. There is no second recogniser to lose the touch to.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let key = TouchpadGestureResolver.action(forTranslation: value.translation)
                        Task { await model.key(key.rawValue) }
                    }
            )
    }
}
