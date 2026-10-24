// Settings window (⌘,): language, output folder, format, duration limit, app filter, microphone.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: RecorderModel

    var body: some View {
        let t = model.t
        Form {
            Section(t("settings.general")) {
                Picker(t("settings.language"), selection: $model.language) {
                    ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
                }
                LabeledContent(t("settings.folder")) {
                    HStack(spacing: 8) {
                        Text((model.outputFolder.path as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                            .help(model.outputFolder.path)
                        Button(t("settings.folder.choose")) { model.chooseFolder() }
                    }
                }
            }

            Section(t("settings.recording")) {
                Picker(t("settings.format"), selection: $model.format) {
                    ForEach(SampleFormat.allCases, id: \.self) { Text(t("format.\($0.rawValue)")).tag($0) }
                }
                Toggle(t("settings.limit"), isOn: $model.limitEnabled)
                if model.limitEnabled {
                    LabeledContent(t("settings.limit.duration")) {
                        DurationField(seconds: $model.limitSeconds, t: t)
                    }
                }
            }
            .disabled(model.isBusy)

            Section {
                Picker(t("settings.app"), selection: $model.appBundleID) {
                    Text(t("settings.app.all")).tag(String?.none)
                    Divider()
                    ForEach(model.runningApps) { Text($0.name).tag(String?.some($0.bundleID)) }
                    if let id = model.appBundleID, !model.runningApps.contains(where: { $0.bundleID == id }) {
                        Text(id).tag(String?.some(id))
                    }
                }
                Picker(t("settings.mic.device"), selection: $model.micDeviceID) {
                    Text(t("mic.default")).tag(String?.none)
                    Divider()
                    ForEach(model.micDevices) { Text($0.name).tag(String?.some($0.id)) }
                }
            } header: {
                HStack {
                    Text(t("settings.sources"))
                    Spacer()
                    Button { model.refreshDevices() } label: {
                        Label(t("settings.refresh"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            } footer: {
                Text(t("settings.sources.footer"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(model.isBusy)
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.refreshDevices() }
    }
}

/// Minutes and seconds with steppers; never below one second.
struct DurationField: View {
    @Binding var seconds: Int
    let t: Strings

    var body: some View {
        let minutes = Binding(get: { seconds / 60 }, set: { seconds = max(1, min(5999, $0) * 60 + seconds % 60) })
        let secs = Binding(get: { seconds % 60 }, set: { seconds = max(1, seconds / 60 * 60 + min(59, max(0, $0))) })
        HStack(spacing: 6) {
            number(minutes, range: 0...5999)
            Text(t("unit.min")).foregroundStyle(.secondary)
            number(secs, range: 0...59)
            Text(t("unit.sec")).foregroundStyle(.secondary)
        }
    }

    private func number(_ value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 2) {
            TextField("", value: value, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 48)
                .labelsHidden()
            Stepper("", value: value, in: range).labelsHidden()
        }
    }
}
