// Level meters for the sources being recorded: green to red over -60…0 dBFS.

import SwiftUI

struct Meters: View {
    @ObservedObject var levels: LiveLevels
    let source: CaptureSource
    let t: Strings

    var body: some View {
        VStack(spacing: 10) {
            if source.includesSystem {
                LevelMeter(icon: CaptureSource.system.symbol, label: t("meter.system"), level: levels.value.system)
            }
            if source.includesMic {
                LevelMeter(icon: CaptureSource.mic.symbol, label: t("meter.mic"), level: levels.value.mic)
            }
        }
    }
}

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
                        .fill(Theme.meterGradient)
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
