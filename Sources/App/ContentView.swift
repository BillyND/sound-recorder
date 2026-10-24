// The main window: source, record button with timer and meters, recent recordings.

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: RecorderModel
    @State private var topHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            // Everything below the title bar row scrolls when the window is short;
            // the recordings card takes the remaining height and scrolls on its own.
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 14) {
                        VStack(spacing: 14) {
                            NoticeList()
                            sourcePicker
                            RecorderCard()
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topHeight = $0 }
                        RecordingsCard()
                            .frame(height: max(220, geo.size.height - topHeight - 14 - 26))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 20)
                }
                .scrollBounceBehavior(.basedOnSize)
                .defaultScrollAnchor(.top)
            }
        }
        .ignoresSafeArea(edges: .top)  // the header row shares the title bar, clear of the window buttons
        .frame(minWidth: 420, idealWidth: 440, maxWidth: 560, minHeight: 520, idealHeight: 780, maxHeight: .infinity)
        .background(Backdrop())
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshPermissions()
            model.reloadRecordings()
        }
        .onDisappear { Task { await model.stopForQuit() } }  // closing the window finalizes the file
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Sound Recorder")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(model.t("app.subtitle"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(model.t("settings.open"))
            .accessibilityLabel(model.t("settings.open"))
        }
        .padding(.leading, 76)  // clear of the window buttons
        .padding(.trailing, 12)
        .padding(.top, 4)
        .frame(height: 40)
    }

    private var sourcePicker: some View {
        VStack(spacing: 8) {
            SourcePicker(selection: $model.source, t: model.t)
                .disabled(model.isBusy)

            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
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
                let selected = selection == source
                Button {
                    withAnimation(.spring(duration: 0.3)) { selection = source }
                } label: {
                    Label(t("source.\(source.rawValue)"), systemImage: icon(source))
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(LinearGradient(colors: [.brand, .brandDeep], startPoint: .top, endPoint: .bottom))
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .card(cornerRadius: 22)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(t("source.label"))
    }

    private func icon(_ source: CaptureSource) -> String {
        switch source {
        case .system: return "speaker.wave.2.fill"
        case .mic: return "mic.fill"
        case .both: return "waveform.and.mic"
        }
    }
}

/// Compact permission notices and errors; each can be dismissed and hides itself once resolved.
struct NoticeList: View {
    @EnvironmentObject var model: RecorderModel

    var body: some View {
        let t = model.t
        VStack(spacing: 8) {
            if model.showsScreenNotice {
                Notice(icon: "rectangle.dashed.badge.record", title: t("perm.screen.title"), message: t("perm.screen.message"),
                       actionTitle: t("perm.open"), action: { model.openPrivacySettings("Privacy_ScreenCapture") },
                       dismissLabel: t("notice.dismiss"), onDismiss: { model.dismiss(.screen) })
            }
            if model.showsMicNotice {
                Notice(icon: "mic.slash", title: t("perm.mic.title"), message: t("perm.mic.message"),
                       actionTitle: t("perm.open"), action: { model.openPrivacySettings("Privacy_Microphone") },
                       dismissLabel: t("notice.dismiss"), onDismiss: { model.dismiss(.mic) })
            }
            if let message = problemMessage {
                Notice(icon: "exclamationmark.triangle", title: t("error.title"), message: message,
                       actionTitle: nil, action: {}, dismissLabel: t("notice.dismiss"), onDismiss: { model.dismiss(.problem) })
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.showsScreenNotice)
        .animation(.easeOut(duration: 0.2), value: model.showsMicNotice)
    }

    private var problemMessage: String? {
        let t = model.t
        switch model.problem {
        case .appNotRunning(let id): return t("error.appNotRunning", model.appName(id))
        case .startTimedOut: return t("error.timeout")
        case .failed(let detail): return t("error.failed", detail)
        default: return nil
        }
    }
}

struct Notice: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: () -> Void
    let dismissLabel: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.orange)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(dismissLabel)
            .accessibilityLabel(dismissLabel)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .card(cornerRadius: 14)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// Record button, timer and per-source level meters.
struct RecorderCard: View {
    @EnvironmentObject var model: RecorderModel

    var body: some View {
        let t = model.t
        VStack(spacing: 6) {
            RecordButton(levels: model.levels, state: model.state,
                         label: model.state == .idle ? t("record.start") : t("record.stop"),
                         action: model.toggle)
            TimerText(clock: model.clock, state: model.state, limit: model.limit, t: t)
            Text(status)
                .font(.callout)
                .foregroundStyle(.secondary)
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

struct TimerText: View {
    @ObservedObject var clock: LiveClock
    let state: RecordingState
    let limit: Double?
    let t: Strings

    var body: some View {
        VStack(spacing: 2) {
            Text(formatClock(state == .idle ? 0 : Double(clock.seconds)))
                .font(.system(size: 44, weight: .light, design: .rounded).monospacedDigit())
                .contentTransition(.identity)
            Group {
                if let limit {
                    if state == .idle {
                        Text(t("timer.limit", formatClock(limit)))
                    } else {
                        Text(t("timer.remaining", formatClock(limit - Double(clock.seconds))))
                    }
                } else {
                    Text(t("timer.untilStop"))
                }
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}

struct Meters: View {
    @ObservedObject var levels: LiveLevels
    let source: CaptureSource
    let t: Strings

    var body: some View {
        VStack(spacing: 10) {
            if source.includesSystem {
                LevelMeter(icon: "speaker.wave.2.fill", label: t("meter.system"), level: levels.value.system)
            }
            if source.includesMic {
                LevelMeter(icon: "mic.fill", label: t("meter.mic"), level: levels.value.mic)
            }
        }
    }
}

/// Recent recordings in the output folder, with play / reveal / delete on hover.
struct RecordingsCard: View {
    @EnvironmentObject var model: RecorderModel
    @State private var pendingDelete: Recording?

    var body: some View {
        let t = model.t
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(t("recent.title")).font(.headline)
                Spacer()
                Button { model.revealFolder() } label: {
                    Label(t("recent.openFolder"), systemImage: "folder")
                }
                .buttonStyle(.borderless)
                .help(model.outputFolder.path)
            }
            .padding(.horizontal, 6)

            if model.recordings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform").font(.system(size: 26, weight: .light))
                    Text(t("recent.empty")).font(.callout)
                }
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.recordings) { recording in
                            RecordingRow(recording: recording, onDelete: { pendingDelete = recording })
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(12)
        .frame(minHeight: 230, idealHeight: 320, maxHeight: .infinity, alignment: .top)
        .card()
        .confirmationDialog(t("delete.title"), isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { recording in
            Button(t("delete.confirm"), role: .destructive) { model.trash(recording) }
            Button(t("cancel"), role: .cancel) {}
        } message: { recording in
            Text(t("delete.message", recording.name))
        }
    }
}

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
                .foregroundStyle(Color.brand)
                .frame(width: 30, height: 30)
                .background(Color.brand.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(recording.name).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                Text(details).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if hovering {
                HStack(spacing: 2) {
                    rowButton("play.fill", t("recent.play")) { model.open(recording) }
                    rowButton("magnifyingglass", t("recent.reveal")) { model.reveal(recording) }
                    rowButton("trash", t("recent.delete"), action: onDelete)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(hovering ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovering = inside } }
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

    private func rowButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }
}
