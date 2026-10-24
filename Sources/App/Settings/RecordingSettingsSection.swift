// File format and the optional automatic stop.

import SwiftUI

struct RecordingSettingsSection: View {
    @EnvironmentObject var model: RecorderModel

    var body: some View {
        let t = model.t
        Section(t("settings.recording")) {
            Picker(t("settings.format"), selection: $model.format) {
                ForEach(SampleFormat.allCases, id: \.self) { Text(t("format.\($0.rawValue)")).tag($0) }
            }
            .pointerCursor()
            Toggle(t("settings.limit"), isOn: $model.limitEnabled)
                .pointerCursor()
            if model.limitEnabled {
                LabeledContent(t("settings.limit.duration")) {
                    DurationField(seconds: $model.limitSeconds, t: t)
                }
            }
        }
    }
}
