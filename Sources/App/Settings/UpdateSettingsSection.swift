// Sparkle update preferences, the current version and a manual check.

import SwiftUI

struct UpdateSettingsSection: View {
    @EnvironmentObject var model: RecorderModel
    @EnvironmentObject var updater: AppUpdater

    var body: some View {
        let t = model.t
        Section {
            Toggle(t("settings.updates.autoCheck"), isOn: $updater.automaticallyChecks)
                .pointerCursor()
            Toggle(t("settings.updates.autoInstall"), isOn: $updater.automaticallyDownloads)
                .pointerCursor()
                .disabled(!updater.automaticallyChecks)
            LabeledContent(t("settings.updates.version")) {
                HStack(spacing: 8) {
                    Text(updater.version)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Button(t("update.check")) { updater.checkForUpdates() }
                        .pointerCursor()
                        .disabled(!updater.canCheckForUpdates)
                }
            }
        } header: {
            Text(t("settings.updates"))
        } footer: {
            Text(updater.postponedVersion.map { t("settings.updates.postponed", $0) } ?? t("settings.updates.footer"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
