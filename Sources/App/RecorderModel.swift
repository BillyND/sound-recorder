// App state: settings (remembered in UserDefaults), the running capture session,
// permissions and the list of recent recordings.

import AppKit
import AVFoundation
import Combine
import SwiftUI

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

/// Values that change while recording, split by update rate so each redraws only
/// its own small view: the clock once per second, meters and pulse at 15 Hz.
final class LiveClock: ObservableObject {
    @Published var seconds = 0
}

struct Levels: Equatable {
    var system: Double = 0  // 0…1 on a -60…0 dBFS scale
    var mic: Double = 0
    var pulse: Double = 0   // 0…1 phase of the record button ring
}

final class LiveLevels: ObservableObject {
    @Published var value = Levels()
}

@MainActor
final class RecorderModel: ObservableObject {
    static let shared = RecorderModel()

    // Settings
    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: "language"); t = Strings(language) }
    }
    @Published var source: CaptureSource { didSet { defaults.set(source.rawValue, forKey: "source") } }
    @Published var format: SampleFormat { didSet { defaults.set(format.rawValue, forKey: "format") } }
    @Published var limitEnabled: Bool { didSet { defaults.set(limitEnabled, forKey: "limitEnabled") } }
    @Published var limitSeconds: Int { didSet { defaults.set(limitSeconds, forKey: "limitSeconds") } }
    @Published var outputFolder: URL { didSet { defaults.set(outputFolder.path, forKey: "outputFolder"); reloadRecordings() } }
    @Published var micDeviceID: String? { didSet { defaults.set(micDeviceID, forKey: "micDeviceID") } }
    @Published var appBundleID: String?  // nil = all apps; not remembered (apps come and go)

    // State
    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var problem: Problem?
    @Published private(set) var lastSaved: CaptureResult?
    @Published private(set) var screenPermission = hasScreenCapturePermission()
    @Published private(set) var micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published private(set) var recordings: [Recording] = []
    @Published private(set) var runningApps: [RunningApp] = []
    @Published private(set) var micDevices: [MicDevice] = []
    @Published private var dismissed: Set<NoticeKind> = []
    let clock = LiveClock()
    let levels = LiveLevels()

    enum NoticeKind { case screen, mic, problem }

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

    private(set) var t: Strings
    var isBusy: Bool { state != .idle }
    var limit: Double? { limitEnabled && limitSeconds > 0 ? Double(limitSeconds) : nil }

    private let defaults = UserDefaults.standard
    private var session: CaptureSession?
    private var startToken: UUID?
    private var startDate = Date()
    private var ticker: Timer?
    private var lastToggle = Date.distantPast

    static let defaultFolder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Music", isDirectory: true)
        .appendingPathComponent("Sound Recorder", isDirectory: true)

    private init() {
        let language = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "") ?? .en
        self.language = language
        t = Strings(language)
        source = CaptureSource(rawValue: defaults.string(forKey: "source") ?? "") ?? .system
        format = SampleFormat(rawValue: defaults.string(forKey: "format") ?? "") ?? .float32
        limitEnabled = defaults.bool(forKey: "limitEnabled")
        limitSeconds = defaults.object(forKey: "limitSeconds") as? Int ?? 300
        outputFolder = defaults.string(forKey: "outputFolder").map { URL(fileURLWithPath: $0, isDirectory: true) } ?? Self.defaultFolder
        micDeviceID = defaults.string(forKey: "micDeviceID")
        refreshDevices()
        reloadRecordings()
    }

    // MARK: Recording

    func toggle() {
        // Ignore a double click: one press starts, the next deliberate one stops.
        guard Date().timeIntervalSince(lastToggle) > 0.4 else { return }
        lastToggle = Date()
        switch state {
        case .idle: start()
        case .recording: Task { await stop() }
        default: break
        }
    }

    func start() {
        guard state == .idle else { return }
        problem = nil
        lastSaved = nil
        refreshPermissions()
        guard screenPermission else {
            _ = CGRequestScreenCaptureAccess()  // lists Sound Recorder in System Settings
            problem = .screenPermission
            return
        }
        do {
            try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        } catch {
            problem = .failed(error.localizedDescription)
            return
        }
        let url = nextFileURL()
        let options = CaptureOptions(source: source, appBundleID: source.includesSystem ? appBundleID : nil,
                                     micDeviceID: micDeviceID, format: format, duration: limit)
        let token = UUID()
        startToken = token
        state = .starting

        // Never hang on a stuck permission prompt or ScreenCaptureKit call.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, self.startToken == token, self.state == .starting else { return }
            self.startToken = nil
            self.state = .idle
            self.problem = .startTimedOut
        }

        Task {
            do {
                let session = try await CaptureSession.start(url: url, options: options) { error in
                    Task { @MainActor in await RecorderModel.shared.captureFailed(error) }
                }
                guard startToken == token else {  // timed out meanwhile: discard
                    _ = await session.stop()
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                startToken = nil
                self.session = session
                startDate = Date()
                clock.seconds = 0
                state = .recording
                startTicker()
            } catch {
                guard startToken == token else { return }
                startToken = nil
                state = .idle
                problem = Self.problem(for: error)
                refreshPermissions()
            }
        }
    }

    func stop() async {
        guard state == .recording, let session else { return }
        state = .stopping
        ticker?.invalidate()
        ticker = nil
        let result = await session.stop()
        self.session = nil
        levels.value = Levels()
        lastSaved = result
        state = .idle
        reloadRecordings()
    }

    /// Used on quit: waits for a start in progress, then stops and finalizes the file.
    func stopForQuit() async {
        while state == .starting { try? await Task.sleep(nanoseconds: 100_000_000) }
        await stop()
    }

    private func captureFailed(_ error: CaptureError) async {
        guard state == .recording else { return }
        await stop()
        problem = Self.problem(for: error)
    }

    private static func problem(for error: Error) -> Problem {
        switch error as? CaptureError {
        case .screenPermissionDenied: return .screenPermission
        case .micPermissionDenied: return .micPermission
        case .appNotRunning(let id): return .appNotRunning(id)
        case .noDisplay: return .failed("no display")
        case .startFailed(let e), .writeFailed(let e), .streamStopped(let e): return .failed(e.localizedDescription)
        case nil: return .failed(error.localizedDescription)
        }
    }

    /// 15 Hz UI tick while recording: clock, meters, pulse and the duration limit.
    private func startTicker() {
        let timer = Timer(timeInterval: 1.0 / 15, repeats: true) { _ in
            Task { @MainActor in RecorderModel.shared.tick() }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        guard state == .recording, let session else { return }
        let elapsed = Date().timeIntervalSince(startDate)
        let seconds = Int(limit.map { min(elapsed, $0) } ?? elapsed)
        if clock.seconds != seconds { clock.seconds = seconds }
        let peaks = session.recorder.takePeaks()
        let old = levels.value
        // Instant attack, smooth release.
        levels.value = Levels(system: max(Self.meterValue(peaks.system), old.system * 0.75),
                              mic: max(Self.meterValue(peaks.mic), old.mic * 0.75),
                              pulse: elapsed.truncatingRemainder(dividingBy: 1.6) / 1.6)
        if let limit, elapsed >= limit + 0.3 { Task { await stop() } }
    }

    private static func meterValue(_ peak: Float) -> Double {
        guard peak > 0 else { return 0 }
        let db = 20 * log10(Double(peak))
        return min(1, max(0, (db + 60) / 60))
    }

    private func nextFileURL() -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let base = "Sound Recorder " + formatter.string(from: Date())
        var url = outputFolder.appendingPathComponent(base + ".wav")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = outputFolder.appendingPathComponent("\(base) (\(n)).wav")
            n += 1
        }
        return url
    }

    // MARK: Permissions, apps and devices

    func refreshPermissions() {
        screenPermission = hasScreenCapturePermission()
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
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
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != own }
            .map { RunningApp(bundleID: $0.bundleIdentifier!, name: $0.localizedName ?? $0.bundleIdentifier!) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        micDevices = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
            .devices.map { MicDevice(id: $0.uniqueID, name: $0.localizedName) }
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
            await MainActor.run { RecorderModel.shared.recordings = Array(list) }
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
