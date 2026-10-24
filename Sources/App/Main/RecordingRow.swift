// One recording: name, date, length and size; actions appear on hover, double-click plays.

import SwiftUI

struct RecordingRow: View {
    @EnvironmentObject var model: RecorderModel
    let recording: Recording
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        let t = model.t
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.badge, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(recording.name).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                Text(details).font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if hovering {
                HStack(spacing: 2) {
                    IconButton(systemImage: "play.fill", label: t("recent.play")) { model.open(recording) }
                    IconButton(systemImage: "magnifyingglass", label: t("recent.reveal")) { model.reveal(recording) }
                    IconButton(systemImage: "trash", label: t("recent.delete"), action: onDelete)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(hovering ? Theme.surfaceRaised : Color.clear, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .contentShape(Rectangle())
        .onHover { inside in withCalmAnimation(Theme.Motion.quick) { hovering = inside } }
        .onTapGesture(count: 2) { model.open(recording) }
        .contextMenu {
            Button(t("recent.play")) { model.open(recording) }
            Button(t("recent.reveal")) { model.reveal(recording) }
            Divider()
            Button(t("recent.delete"), role: .destructive, action: onDelete)
        }
    }

    private var details: String {
        let date = recording.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(model.language.locale))
        let size = ByteCountFormatter.string(fromByteCount: recording.bytes, countStyle: .file)
        return "\(date)  ·  \(formatClock(recording.seconds))  ·  \(size)"
    }
}
