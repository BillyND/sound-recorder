// Record button, timer, status line and per-source level meters. This card redraws only when the
// recording state changes; the fast-changing parts observe their own live objects.

import SwiftUI

struct RecorderCard: View {
    @EnvironmentObject var model: RecorderModel

    var body: some View {
        let t = model.t
        VStack(spacing: 6) {
            RecordButton(pulse: model.pulse, state: model.state,
                         label: model.state == .idle ? t("record.start") : t("record.stop"),
                         action: model.toggle)
            TimerText(clock: model.clock, state: model.state, limit: model.limit, t: t)
            Text(status)
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(minHeight: 34)
            Meters(levels: model.levels, source: model.source, t: t)
                .padding(.top, 6)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .card()
    }

    private var status: String {
        let t = model.t
        switch model.state {
        case .starting: return t("status.starting")
        case .recording: return t("status.recording")
        case .stopping: return t("status.saving")
        case .idle:
            guard let saved = model.lastSaved else { return t("status.ready") }
            var text = t("status.saved", saved.url.deletingPathExtension().lastPathComponent, formatClock(saved.seconds))
            if saved.clippedSamples > 0 { text += "\n" + t("status.clipped", saved.clippedSamples) }
            return text
        }
    }
}
