// Reusable pieces of the Sound Recorder look: accent color, glass cards, the record
// button, level meters and time formatting.

import SwiftUI

extension Color {
    static let brand = Color(red: 0.98, green: 0.30, blue: 0.42)
    static let brandDeep = Color(red: 0.86, green: 0.16, blue: 0.36)
}

extension View {
    /// Liquid Glass on macOS 26, a material card before that.
    @ViewBuilder func card(cornerRadius: CGFloat = 22) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

/// Soft accent glow behind the glass, adapting to light and dark mode.
struct Backdrop: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(colors: [Color.brand.opacity(0.20), .clear], center: .topLeading, startRadius: 0, endRadius: 460)
            RadialGradient(colors: [Color.brandDeep.opacity(0.12), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 520)
        }
        .ignoresSafeArea()
    }
}

/// "1:05" or "1:02:05".
func formatClock(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded(.down)))
    let h = total / 3600, m = total / 60 % 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
}

/// Large circular record / stop button. While recording, a ring pulses outward;
/// it is driven by the 15 Hz recording tick, so nothing animates at display rate.
struct RecordButton: View {
    let levels: LiveLevels
    let state: RecordingState
    let label: String
    let action: () -> Void

    var body: some View {
        let recording = state == .recording
        Button(action: action) {
            ZStack {
                if recording { PulseRing(levels: levels) }
                Circle()
                    .fill(LinearGradient(colors: [.brand, .brandDeep], startPoint: .top, endPoint: .bottom))
                    .shadow(color: Color.brand.opacity(recording ? 0.55 : 0.35), radius: recording ? 18 : 10, y: 4)
                Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1)
                switch state {
                case .starting, .stopping:
                    ProgressView().controlSize(.small).tint(.white)
                case .recording:
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white).frame(width: 26, height: 26)
                case .idle:
                    Circle().fill(.white).frame(width: 28, height: 28)
                }
            }
            .frame(width: 84, height: 84)
            .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .frame(width: 116, height: 116)
        .keyboardShortcut("r", modifiers: .command)
        .disabled(state == .starting || state == .stopping)
        .help(label + "  ⌘R")
        .accessibilityLabel(label)
    }
}

struct PulseRing: View {
    @ObservedObject var levels: LiveLevels

    var body: some View {
        let phase = levels.value.pulse
        Circle()
            .stroke(Color.brand.opacity(0.55 * (1 - phase)), lineWidth: 3)
            .scaleEffect(1 + 0.32 * phase)
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Horizontal level meter: green to red over -60…0 dBFS.
struct LevelMeter: View {
    let icon: String
    let label: String
    let level: Double

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [.green, .yellow, .orange, .brand], startPoint: .leading, endPoint: .trailing))
                        .mask(alignment: .leading) {
                            Capsule().frame(width: geo.size.width * level)
                        }
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(level * 100))%")
    }
}
