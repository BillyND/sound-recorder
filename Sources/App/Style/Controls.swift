// Small shared controls: the press-to-shrink button style and the borderless icon button
// used for row actions and notice close buttons.

import SwiftUI

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .calmAnimation(Theme.Motion.quick, value: configuration.isPressed)
    }
}

/// An SF Symbol button with a tooltip and accessibility label.
struct IconButton: View {
    let systemImage: String
    let label: String
    var size: CGFloat = 12
    var weight: Font.Weight = .semibold
    var frame: CGFloat = 26
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: weight))
                .frame(width: frame, height: frame)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .pointerCursor()
        .help(label)
        .accessibilityLabel(label)
    }
}
