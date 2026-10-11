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
}

/// The touch surface shown in place of the directional pad in touchpad mode.
struct TouchpadSurface: View {
    @ObservedObject var model: AppModel

    var body: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.quaternary)
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "hand.tap")
                        .font(.largeTitle)
                    Text("Swipe to move, tap to select")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .highPriorityGesture(
                DragGesture(minimumDistance: TouchpadGestureResolver.threshold)
                    .onEnded { value in
                        guard let key = TouchpadGestureResolver.key(forTranslation: value.translation) else { return }
                        Task { await model.key(key.rawValue) }
                    }
            )
            .onTapGesture {
                Task { await model.key(TouchKey.select.rawValue) }
            }
    }
}
