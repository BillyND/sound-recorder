// Plain values the app model works with: recording state, problems to show, files, apps and devices.

import Foundation

enum RecordingState { case idle, starting, recording, stopping }

/// Something the user should know about; rendered in the current language.
enum Problem: Equatable {
    case screenPermission, micPermission, startTimedOut
    case appNotRunning(String)
    case failed(String)
}

struct Recording: Identifiable, Equatable {
    let url: URL
    let date: Date
    let seconds: Double
    let bytes: Int64
    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

struct RunningApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    var id: String { bundleID }
}

struct MicDevice: Identifiable, Hashable {
    let id: String  // AVCaptureDevice.uniqueID
    let name: String
}
