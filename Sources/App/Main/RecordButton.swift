// Large circular record / stop button. While recording, a ring pulses outward; it is driven by
// the 15 Hz recording tick through LivePulse, so nothing animates at display rate, and it is not
// shown at all under Reduce Motion.

import SwiftUI

struct RecordButton: View {
    let pulse: LivePulse
    let state: RecordingState
    let label: String
    let action: () -> Void

    var body: some View {
        let recording = state == .recording
        Button(action: action) {
            ZStack {
                if recording { PulseRing(pulse: pulse) }
                Circle()
                    .fill(Theme.accentFill)
                    .shadow(color: Theme.shadow, radius: 6, y: 2)
                glyph
            }
            .frame(width: 84, height: 84)
            .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .disabled(state == .starting || state == .stopping)
        .pointerCursor()
        .frame(width: 116, height: 116)
        .keyboardShortcut("r", modifiers: .command)
        .help(label + "  ⌘R")
        .accessibilityLabel(label)
    }

    @ViewBuilder private var glyph: some View {
        switch state {
        case .starting, .stopping:
            ProgressView().controlSize(.small).tint(Theme.onAccent)
        case .recording:
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.onAccent).frame(width: 26, height: 26)
        case .idle:
            Circle().fill(Theme.onAccent).frame(width: 28, height: 28)
        }
    }
}

private struct PulseRing: View {
    @ObservedObject var pulse: LivePulse
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let phase = pulse.phase
        if !reduceMotion {
            Circle()
                .stroke(Theme.accent.opacity(0.5 * (1 - phase)), lineWidth: 2)
                .scaleEffect(1 + 0.3 * phase)
        }
    }
}
