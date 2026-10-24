// Language and output folder.

import SwiftUI

struct GeneralSettingsSection: View {
    @EnvironmentObject var model: RecorderModel

    var body: some View {
        let t = model.t
        Section(t("settings.general")) {
            Picker(t("settings.language"), selection: $model.language) {
                ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
            }
            .pointerCursor()
            LabeledContent(t("settings.folder")) {
                HStack(spacing: 8) {
                    Text((model.outputFolder.path as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .help(model.outputFolder.path)
                    Button(t("settings.folder.choose")) { model.chooseFolder() }
                        .pointerCursor()
                }
            }
        }
    }
}
