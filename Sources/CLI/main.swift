// sysaudio-record: record macOS system audio (speaker output) and/or a microphone
// to a WAV file using ScreenCaptureKit. No virtual audio driver needed.
// The capture engine is shared with the Sound Recorder app (Sources/Engine).
//
// Usage: sysaudio-record <output.wav> [--duration SECONDS] [--app BUNDLE_ID]
//                        [--source system|mic|both] [--format 16|24|f32]
// Output: 48 kHz stereo WAV, 16-bit signed integer PCM unless --format says otherwise.

import Foundation

let usage = "usage: sysaudio-record <output.wav> [--duration SECONDS] [--app BUNDLE_ID] [--source system|mic|both] [--format 16|24|f32]"

let permissionHelp = """
error: Screen & System Audio Recording permission is missing for this terminal.
Enable it for your terminal app (Terminal, iTerm2, Ghostty, VS Code, ...) in:
  System Settings → Privacy & Security → Screen & System Audio Recording
then quit and reopen the terminal app and run this command again.
"""

let micPermissionHelp = """
error: Microphone permission is missing for this terminal.
Enable it for your terminal app in:
  System Settings → Privacy & Security → Microphone
then quit and reopen the terminal app and run this command again.
"""

func eprint(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func fail(_ message: String) -> Never {
    eprint(message)
    exit(1)
}

func describe(_ error: CaptureError) -> String {
    switch error {
    case .screenPermissionDenied: return permissionHelp
    case .micPermissionDenied: return micPermissionHelp
    case .noDisplay: return "error: no display found (a display filter is required)"
    case .appNotRunning(let id): return "error: no running application with bundle id '\(id)'"
    case .startFailed(let e): return "error: could not start capture: \(e.localizedDescription)"
    case .writeFailed(let e): return "error: writing audio failed: \(e.localizedDescription)"
    case .streamStopped(let e): return "error: capture stopped: \(e.localizedDescription)"
    }
}

// MARK: - Arguments

var outputPath: String?
var options = CaptureOptions(format: .int16)

var argIterator = CommandLine.arguments.dropFirst().makeIterator()
while let arg = argIterator.next() {
    switch arg {
    case "-h", "--help":
        print(usage)
        exit(0)
    case "--duration":
        guard let value = argIterator.next(), let seconds = Double(value), seconds > 0 else {
            fail("error: --duration needs a positive number of seconds\n\(usage)")
        }
        options.duration = seconds
    case "--app":
        guard let value = argIterator.next(), !value.isEmpty else {
            fail("error: --app needs a bundle identifier (e.g. com.google.Chrome)\n\(usage)")
        }
        options.appBundleID = value
    case "--source":
        guard let value = argIterator.next(), let source = CaptureSource(rawValue: value) else {
            fail("error: --source needs system, mic or both\n\(usage)")
        }
        options.source = source
    case "--format":
        guard let value = argIterator.next(), let format = SampleFormat(rawValue: value) else {
            fail("error: --format needs 16, 24 or f32\n\(usage)")
        }
        options.format = format
    default:
        if arg.hasPrefix("-") || outputPath != nil { fail("error: unexpected argument '\(arg)'\n\(usage)") }
        outputPath = arg
    }
}
guard let outputPath else { fail(usage) }
if options.appBundleID != nil, !options.source.includesSystem { fail("error: --app only applies to system audio\n\(usage)") }
let outputURL = URL(fileURLWithPath: outputPath).standardizedFileURL

// MARK: - Main flow

var session: CaptureSession?
var finishing = false
var started = false

/// Stops capture, finalizes the file and exits. Runs on the main queue.
func finish(exitCode: Int32, message: String? = nil) {
    if finishing { return }
    finishing = true
    if let message { eprint(message) }
    Task {
        guard let session else { exit(exitCode) }
        let result = await session.stop()
        print(String(format: "saved: %@ (%.2f s, 48 kHz stereo %@)", outputURL.path, result.seconds, options.format.summary))
        if result.clippedSamples > 0 {
            eprint("warning: \(result.clippedSamples) samples were above full scale and clipped (use --format f32 to keep them)")
        }
        exit(exitCode)
    }
}

func start() async {
    do {
        let s = try await CaptureSession.start(url: outputURL, options: options) { error in
            DispatchQueue.main.async { finish(exitCode: 1, message: describe(error)) }
        }
        session = s
        if !s.capturedApps.isEmpty {
            eprint("capturing app audio from: " + s.capturedApps.map { "\($0.applicationName) (\($0.bundleIdentifier), pid \($0.processID))" }.joined(separator: ", "))
        }
    } catch let error as CaptureError {
        fail(describe(error))
    } catch {
        fail("error: could not start capture: \(error.localizedDescription)")
    }

    started = true
    var scope = options.appBundleID.map { "app \($0)" } ?? "all system audio"
    if options.source == .mic { scope = "microphone" } else if options.source == .both { scope += " + microphone" }
    let until = options.duration.map { String(format: "for %.1f s", $0) } ?? "until Ctrl-C"
    print("recording… (\(scope), \(until)) → \(outputURL.path)")

    if let duration = options.duration {
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.3) { finish(exitCode: 0) }
    }
}

setvbuf(stdout, nil, _IOLBF, 0)

// Stop cleanly on Ctrl-C / SIGTERM so the WAV header gets finalized.
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler { finish(exitCode: 0) }
    source.resume()
    signalSources.append(source)
}

// Startup watchdog: never hang silently (e.g. on a stuck permission dialog).
DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
    if !started { fail("error: timed out starting capture.\n" + permissionHelp) }
}

Task { await start() }
dispatchMain()
