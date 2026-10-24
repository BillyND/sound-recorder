// Permissions, running apps, microphones and the recordings in the output folder.
// Slow lookups run off the main thread; results are published only when they change,
// so returning to the app does not redraw the window for nothing.

import AppKit
import AVFoundation

extension RecorderModel {
    // MARK: Notices

    var showsScreenNotice: Bool {
        problem == .screenPermission || (!screenPermission && !dismissed.contains(.screen))
    }
    var showsMicNotice: Bool {
        let blocked = source.includesMic && (micStatus == .denied || micStatus == .restricted)
        return problem == .micPermission || (blocked && !dismissed.contains(.mic))
    }

    func dismiss(_ kind: NoticeKind) {
        dismissed.insert(kind)
        switch (kind, problem) {
        case (.screen, .screenPermission?), (.mic, .micPermission?), (.problem, _): problem = nil
        default: break
        }
    }

    // MARK: Permissions, apps and devices

    func refreshPermissions() {
        let screen = hasScreenCapturePermission()
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        if screenPermission != screen { screenPermission = screen }
        if micStatus != mic { micStatus = mic }
        if screenPermission, problem == .screenPermission { problem = nil }
        if micStatus == .authorized, problem == .micPermission { problem = nil }
    }

    func openPrivacySettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    func refreshDevices() {
        let own = Bundle.main.bundleIdentifier
        Task.detached(priority: .userInitiated) {
            // Both lookups are thread-safe; device discovery can take tens of milliseconds.
            let apps = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != own }
                .map { RunningApp(bundleID: $0.bundleIdentifier!, name: $0.localizedName ?? $0.bundleIdentifier!) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            let mics = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
                .devices.map { MicDevice(id: $0.uniqueID, name: $0.localizedName) }
            await MainActor.run {
                let model = RecorderModel.shared
                if model.runningApps != apps { model.runningApps = apps }
                if model.micDevices != mics { model.micDevices = mics }
            }
        }
    }

    func appName(_ bundleID: String) -> String {
        runningApps.first { $0.bundleID == bundleID }?.name ?? bundleID
    }

    var micName: String {
        micDeviceID.flatMap { id in micDevices.first { $0.id == id }?.name } ?? t("mic.default")
    }

    // MARK: Output folder and recordings

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = outputFolder
        panel.prompt = t("settings.folder.choose")
        if panel.runModal() == .OK, let url = panel.url { outputFolder = url }
    }

    func reloadRecordings() {
        let folder = outputFolder
        let current = session?.url
        Task.detached(priority: .utility) {
            let keys: [URLResourceKey] = [.creationDateKey, .fileSizeKey]
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)) ?? []
            let list = files
                .filter { $0.pathExtension.lowercased() == "wav" && $0 != current }
                .compactMap { url -> Recording? in
                    let values = try? url.resourceValues(forKeys: Set(keys))
                    let file = try? AVAudioFile(forReading: url)
                    let seconds = file.map { Double($0.length) / $0.fileFormat.sampleRate } ?? 0
                    return Recording(url: url, date: values?.creationDate ?? .distantPast, seconds: seconds, bytes: Int64(values?.fileSize ?? 0))
                }
                .sorted { $0.date > $1.date }
                .prefix(50)
            await MainActor.run {
                let model = RecorderModel.shared
                if model.recordings != Array(list) { model.recordings = Array(list) }
            }
        }
    }

    func open(_ recording: Recording) { NSWorkspace.shared.open(recording.url) }
    func reveal(_ recording: Recording) { NSWorkspace.shared.activateFileViewerSelecting([recording.url]) }
    func revealFolder() {
        try? FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(outputFolder)
    }

    func trash(_ recording: Recording) {
        do {
            try FileManager.default.trashItem(at: recording.url, resultingItemURL: nil)
        } catch {
            problem = .failed(error.localizedDescription)
        }
        reloadRecordings()
    }
}
