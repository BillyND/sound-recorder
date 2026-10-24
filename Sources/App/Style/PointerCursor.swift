// Pointing-hand cursor over clickable controls, and only while they are enabled.
// Apply it directly on the control, inside any .disabled(), so it sees the enabled state.

import SwiftUI

private struct PointerCursor: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content.pointerStyle(isEnabled ? .link : nil)
    }
}

extension View {
    func pointerCursor() -> some View { modifier(PointerCursor()) }
}
