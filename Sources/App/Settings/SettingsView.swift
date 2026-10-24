// Settings window (⌘,): general, recording, sources and updates sections.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: RecorderModel

    var body: some View {
        Form {
            GeneralSettingsSection()
                .overlayScrollers()  // the grouped form is a scroll view too
            RecordingSettingsSection()
                .disabled(model.isBusy)
            SourcesSettingsSection()
                .disabled(model.isBusy)
            UpdateSettingsSection()
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.refreshDevices() }
    }
}
