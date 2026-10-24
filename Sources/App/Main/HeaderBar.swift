// Title row sharing the window's title bar: app name, subtitle and the Settings button.

import SwiftUI

struct HeaderBar: View {
    @EnvironmentObject var model: RecorderModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Sound Recorder")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(model.t("app.subtitle"))
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .foregroundStyle(Theme.textSecondary)
            .help(model.t("settings.open"))
            .accessibilityLabel(model.t("settings.open"))
        }
        .padding(.leading, 76)  // clear of the window buttons
        .padding(.trailing, 12)
        .padding(.top, 4)
        .frame(height: 40)
    }
}
