// Minutes and seconds with steppers for the automatic stop.

import SwiftUI

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
            Stepper("", value: value, in: range).labelsHidden().pointerCursor()
        }
    }
}
