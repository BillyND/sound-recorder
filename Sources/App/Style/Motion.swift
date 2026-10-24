// Animation helpers that honour System Settings → Accessibility → Display → Reduce Motion:
// with it on, changes happen instantly instead of animating.

import SwiftUI

private struct CalmAnimation<Value: Equatable>: ViewModifier {
    let animation: Animation
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// Animates changes of `value` with a short theme curve, or not at all under Reduce Motion.
    func calmAnimation<Value: Equatable>(_ animation: Animation = Theme.Motion.standard, value: Value) -> some View {
        modifier(CalmAnimation(animation: animation, value: value))
    }
}

/// `withAnimation` that skips the animation under Reduce Motion.
@MainActor func withCalmAnimation(_ animation: Animation = Theme.Motion.standard, _ body: () -> Void) {
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { body() } else { withAnimation(animation, body) }
}
