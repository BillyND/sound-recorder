// Which app's audio to record and which microphone to use.

import SwiftUI

struct SourcesSettingsSection: View {
    @EnvironmentObject var model: RecorderModel

    var body: some View {
        let t = model.t
        Section {
            Picker(t("settings.app"), selection: $model.appBundleID) {
                Text(t("settings.app.all")).tag(String?.none)
                Divider()
                ForEach(model.runningApps) { Text($0.name).tag(String?.some($0.bundleID)) }
                if let id = model.appBundleID, !model.runningApps.contains(where: { $0.bundleID == id }) {
                    Text(id).tag(String?.some(id))
                }
            }
            .pointerCursor()
            Picker(t("settings.mic.device"), selection: $model.micDeviceID) {
                Text(t("mic.default")).tag(String?.none)
                Divider()
                ForEach(model.micDevices) { Text($0.name).tag(String?.some($0.id)) }
            }
            .pointerCursor()
        } header: {
            HStack {
                Text(t("settings.sources"))
                Spacer()
                Button { model.refreshDevices() } label: {
                    Label(t("settings.refresh"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .pointerCursor()
            }
        } footer: {
            Text(t("settings.sources.footer"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
