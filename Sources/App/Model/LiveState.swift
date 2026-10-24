// Values that change while recording, each in its own small observable object so only the view
// showing it redraws: the clock once per second, meters and the record-button pulse at up to 15 Hz.
// Each publishes only when its value actually changes, so silence or a paused UI costs nothing.

import Foundation

final class LiveClock: ObservableObject {
    @Published private(set) var seconds = 0
    func set(_ value: Int) { if seconds != value { seconds = value } }
}

struct Levels: Equatable {
    var system: Double = 0  // 0…1 on a -60…0 dBFS scale
    var mic: Double = 0
}

final class LiveLevels: ObservableObject {
    @Published private(set) var value = Levels()
    /// Rounded down to 1 % steps: finer changes are invisible on the meter and would only cost redraws
    /// (rounding down also lets a decaying meter reach zero and go quiet).
    func set(_ levels: Levels) {
        let rounded = Levels(system: (levels.system * 100).rounded(.down) / 100, mic: (levels.mic * 100).rounded(.down) / 100)
        if value != rounded { value = rounded }
    }
}

/// 0…1 phase of the ring around the record button while recording.
final class LivePulse: ObservableObject {
    @Published private(set) var phase = 0.0
    func set(_ value: Double) { if phase != value { phase = value } }
}
