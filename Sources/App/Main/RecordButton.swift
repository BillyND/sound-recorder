// Large circular record / stop button. While recording, a ring pulses outward; it is driven by
// the 15 Hz recording tick through LivePulse, so nothing animates at display rate.

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
                    .fill(Theme.brandGradient)
                    .shadow(color: Theme.brand.opacity(recording ? 0.55 : 0.35), radius: recording ? 18 : 10, y: 4)
                Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1)
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
            ProgressView().controlSize(.small).tint(.white)
        case .recording:
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white).frame(width: 26, height: 26)
        case .idle:
            Circle().fill(.white).frame(width: 28, height: 28)
        }
    }
}

private struct PulseRing: View {
    @ObservedObject var pulse: LivePulse

    var body: some View {
        let phase = pulse.phase
        Circle()
            .stroke(Theme.brand.opacity(0.55 * (1 - phase)), lineWidth: 3)
            .scaleEffect(1 + 0.32 * phase)
    }
}
