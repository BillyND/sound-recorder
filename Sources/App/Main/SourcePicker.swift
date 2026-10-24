// Source choice (system, microphone, both) and a one-line summary of what will be recorded.

import SwiftUI

struct SourceSection: View {
    @EnvironmentObject var model: RecorderModel

    var body: some View {
        VStack(spacing: 8) {
            SourcePicker(selection: $model.source, t: model.t)
                .disabled(model.isBusy)
            Text(summary)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// e.g. "All apps · MacBook Pro Microphone · 32-bit float WAV"
    private var summary: String {
        let t = model.t
        var parts: [String] = []
        if model.source.includesSystem {
            parts.append(model.appBundleID.map { t("summary.app", model.appName($0)) } ?? t("settings.app.all"))
        }
        if model.source.includesMic { parts.append(model.micName) }
        parts.append(t("format.short.\(model.format.rawValue)"))
        return parts.joined(separator: "  ·  ")
    }
}

/// Segmented source control with SF Symbols and a sliding accent capsule.
struct SourcePicker: View {
    @Binding var selection: CaptureSource
    let t: Strings
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(CaptureSource.allCases, id: \.self) { source in
                segment(source)
            }
        }
        .padding(4)
        .card()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(t("source.label"))
    }

    private func segment(_ source: CaptureSource) -> some View {
        let selected = selection == source
        return Button {
            withCalmAnimation { selection = source }
        } label: {
            Label(t("source.\(source.rawValue)"), systemImage: source.symbol)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(selected ? Theme.onAccent : Theme.textPrimary)
                .background {
                    if selected {
                        Capsule()
                            .fill(Theme.accentFill)
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension CaptureSource {
    var symbol: String {
        switch self {
        case .system: return "speaker.wave.2.fill"
        case .mic: return "mic.fill"
        case .both: return "waveform.and.mic"
        }
    }
}
