// App state: settings (remembered in UserDefaults) and the running capture session.
// Permissions, apps, devices and the recordings list live in RecorderModel+Library.swift.

import AVFoundation
import SwiftUI

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

    // State. Setters are internal only for RecorderModel+Library.swift; views never write them.
    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var lastSaved: CaptureResult?
    @Published var problem: Problem?
    @Published var screenPermission = hasScreenCapturePermission()
    @Published var micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published var recordings: [Recording] = []
    @Published var runningApps: [RunningApp] = []
    @Published var micDevices: [MicDevice] = []
    @Published var dismissed: Set<NoticeKind> = []
    let clock = LiveClock()
    let levels = LiveLevels()
    let pulse = LivePulse()

    enum NoticeKind { case screen, mic, problem }

    private(set) var t: Strings
    var isBusy: Bool { state != .idle }
    var limit: Double? { limitEnabled && limitSeconds > 0 ? Double(limitSeconds) : nil }

    private let defaults = UserDefaults.standard
    var session: CaptureSession?
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
                clock.set(0)
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
        levels.set(Levels())
        pulse.set(0)
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

    /// 15 Hz UI tick while recording: clock, meters, pulse and the duration limit. The timer fires on
    /// the main run loop, so it updates the live objects directly instead of scheduling a task per tick.
    private func startTicker() {
        let timer = Timer(timeInterval: 1.0 / 15, repeats: true) { _ in
            MainActor.assumeIsolated { RecorderModel.shared.tick() }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        guard state == .recording, let session else { return }
        let elapsed = Date().timeIntervalSince(startDate)
        clock.set(Int(limit.map { min(elapsed, $0) } ?? elapsed))
        let peaks = session.recorder.takePeaks()
        let old = levels.value
        // Instant attack, smooth release.
        levels.set(Levels(system: max(Self.meterValue(peaks.system), old.system * 0.75),
                          mic: max(Self.meterValue(peaks.mic), old.mic * 0.75)))
        pulse.set(elapsed.truncatingRemainder(dividingBy: 1.6) / 1.6)
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
}
