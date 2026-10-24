// Elapsed time with the limit or remaining time under it; redraws once per second.

import SwiftUI

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
            caption
                .font(.callout.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var caption: Text {
        guard let limit else { return Text(t("timer.untilStop")) }
        return state == .idle
            ? Text(t("timer.limit", formatClock(limit)))
            : Text(t("timer.remaining", formatClock(limit - Double(clock.seconds))))
    }
}
