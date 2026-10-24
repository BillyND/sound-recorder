// CaptureEngine: record macOS system audio and/or a microphone to a WAV file
// with ScreenCaptureKit. Shared by the sysaudio-record CLI and the Sound Recorder app.
//
// Audio arrives as 48 kHz float32 straight from ScreenCaptureKit and is written
// without gain or processing. "Both" mixes system audio and the microphone by
// presentation timestamp (both share the stream's host clock).

import Accelerate
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

let sampleRate = 48_000.0
let channels = 2

enum CaptureSource: String, CaseIterable {
    case system, mic, both
    var includesSystem: Bool { self != .mic }
    var includesMic: Bool { self != .system }
}

enum SampleFormat: String, CaseIterable {
    case float32 = "f32", int24 = "24", int16 = "16"
    var bitDepth: Int {
        switch self {
        case .float32: return 32
        case .int24: return 24
        case .int16: return 16
        }
    }
    var isFloat: Bool { self == .float32 }
    var summary: String { isFloat ? "32-bit float" : "\(bitDepth)-bit PCM" }
}

struct CaptureOptions {
    var source: CaptureSource = .system
    var appBundleID: String?  // system audio from this app (and its helpers) only
    var micDeviceID: String?  // AVCaptureDevice.uniqueID; nil = system default input
    var format: SampleFormat = .float32
    var duration: Double?
}

enum CaptureError: Error {
    case screenPermissionDenied
    case micPermissionDenied
    case noDisplay
    case appNotRunning(String)
    case startFailed(Error)
    case writeFailed(Error)
    case streamStopped(Error)
}

enum Track: Int {
    case system = 0, mic = 1
}

// MARK: - Permissions

/// Screen & System Audio Recording permission (needed for every SCStream, even mic-only).
func hasScreenCapturePermission() -> Bool { CGPreflightScreenCaptureAccess() }

/// Microphone permission; asks once when undecided.
func requestMicAccess() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: return true
    case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
    default: return false
    }
}

func isPermissionError(_ error: Error) -> Bool {
    let ns = error as NSError
    return ns.domain == SCStreamErrorDomain && ns.code == SCStreamError.userDeclined.rawValue
}

// MARK: - Recorder

/// Receives audio sample buffers from SCStream, mixes the active tracks on a
/// timeline and appends finished frames to the WAV file. Everything except
/// `takePeaks()` runs on `queue` (the stream's sample handler queue).
final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "sysaudio-record.audio", qos: .userInitiated)
    private var file: AVAudioFile?
    private let format: SampleFormat
    private let tracks: [Track]
    private let frameLimit: AVAudioFramePosition?
    private(set) var framesWritten: AVAudioFramePosition = 0
    private(set) var clippedSamples = 0
    var onFatalError: ((CaptureError) -> Void)?

    // Mix timeline: pending[ch][i] is the frame at absolute position pendingStart + i
    // (absolute position = host-clock seconds × sample rate).
    private var pending: [[Float]] = Array(repeating: [], count: channels)
    private var pendingStart: Int64?
    private var cursor: [Track: Int64] = [:]  // where each track's next buffer is expected
    private var converters: [Track: AVAudioConverter] = [:]
    /// How long a silent or late track may hold back writing before it counts as silence.
    private let maxLag: Int64 = 24_000

    private let peakLock = NSLock()
    private var peaks: [Float] = [0, 0]

    init(url: URL, format: SampleFormat, tracks: [Track], duration: Double?) throws {
        // File format: the chosen PCM/float depth. Processing format: float32
        // non-interleaved, which is what ScreenCaptureKit delivers.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: format.bitDepth,
            AVLinearPCMIsFloatKey: format.isFloat,
            AVLinearPCMIsBigEndianKey: false,
        ]
        file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        self.format = format
        self.tracks = tracks
        frameLimit = duration.map { AVAudioFramePosition(($0 * sampleRate).rounded()) }
    }

    var isFull: Bool { frameLimit.map { framesWritten >= $0 } ?? false }

    /// Highest sample magnitude per track since the last call. Safe from any thread.
    func takePeaks() -> (system: Float, mic: Float) {
        peakLock.lock()
        defer { peaks = [0, 0]; peakLock.unlock() }
        return (peaks[0], peaks[1])
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        let track: Track
        switch type {
        case .audio: track = .system
        case .microphone: track = .mic
        default: return  // video frames are mandatory but unused
        }
        guard tracks.contains(track), sampleBuffer.isValid, file != nil, !isFull,
              let buffer = floatBuffer(from: sampleBuffer, track: track)
        else { return }
        let frame = Int64((sampleBuffer.presentationTimeStamp.seconds * sampleRate).rounded())
        add(buffer, track: track, at: frame)
        writeReadyFrames()
    }

    /// Copies a sample buffer into a 48 kHz float32 buffer. ScreenCaptureKit
    /// already delivers that; a converter is only made if a device does not.
    private func floatBuffer(from sampleBuffer: CMSampleBuffer, track: Track) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(sampleBuffer.numSamples)
        guard frameCount > 0, let desc = sampleBuffer.formatDescription,
              case let incoming = AVAudioFormat(cmAudioFormatDescription: desc),
              let buffer = AVAudioPCMBuffer(pcmFormat: incoming, frameCapacity: frameCount)
        else { return nil }
        buffer.frameLength = frameCount
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frameCount), into: buffer.mutableAudioBufferList)
        guard status == noErr else { return nil }
        if incoming.commonFormat == .pcmFormatFloat32, incoming.sampleRate == sampleRate { return buffer }

        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                         channels: incoming.channelCount, interleaved: false)
        else { return nil }
        if converters[track]?.inputFormat != incoming { converters[track] = AVAudioConverter(from: incoming, to: target) }
        let capacity = AVAudioFrameCount((Double(frameCount) * sampleRate / incoming.sampleRate).rounded(.up)) + 16
        guard let converter = converters[track],
              let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity)
        else { return nil }
        var consumed = false
        converter.convert(to: output, error: nil) { _, inputStatus in
            if consumed { inputStatus.pointee = .noDataNow; return nil }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        return output.frameLength > 0 ? output : nil
    }

    /// Mixes a buffer into the timeline at its timestamp. A mono buffer goes to both channels.
    private func add(_ buffer: AVAudioPCMBuffer, track: Track, at ptsFrame: Int64) {
        guard let source = buffer.floatChannelData else { return }
        let count = Int(buffer.frameLength)
        let inChannels = Int(buffer.format.channelCount)
        let stride = buffer.stride

        // Keep a track contiguous across small timestamp jitter. A real gap (e.g.
        // ScreenCaptureKit skipping buffers while nothing plays) stays silent.
        var start = ptsFrame
        if let expected = cursor[track], abs(ptsFrame - expected) <= 480 { start = expected }
        cursor[track] = start + Int64(count)
        if pendingStart == nil { pendingStart = start }

        var peak: Float = 0
        let offset = Int(start - pendingStart!)
        let skip = max(0, -offset)  // frames before pendingStart were already written
        for ch in 0..<min(inChannels, channels) {
            var channelPeak: Float = 0
            vDSP_maxmgv(channelPointer(source, ch, buffer.format.isInterleaved), stride, &channelPeak, vDSP_Length(count))
            peak = max(peak, channelPeak)
        }
        peakLock.lock()
        peaks[track.rawValue] = max(peaks[track.rawValue], peak)
        peakLock.unlock()

        guard skip < count else { return }
        let end = offset + count
        for ch in 0..<channels {
            if pending[ch].count < end { pending[ch].append(contentsOf: repeatElement(0, count: end - pending[ch].count)) }
            let input = channelPointer(source, min(ch, inChannels - 1), buffer.format.isInterleaved) + skip * stride
            pending[ch].withUnsafeMutableBufferPointer { dst in
                let out = dst.baseAddress! + offset + skip
                vDSP_vadd(input, stride, out, 1, out, 1, vDSP_Length(count - skip))
            }
        }
    }

    private func channelPointer(_ data: UnsafePointer<UnsafeMutablePointer<Float>>, _ ch: Int, _ interleaved: Bool) -> UnsafeMutablePointer<Float> {
        interleaved ? data[0] + ch : data[ch]
    }

    /// Writes the frames every active track has delivered (or that are older than `maxLag`).
    private func writeReadyFrames() {
        guard let base = pendingStart else { return }
        let ends = tracks.compactMap { cursor[$0] }
        guard let latest = ends.max() else { return }
        var ready = ends.count == tracks.count ? ends.min()! : base
        ready = max(ready, latest - maxLag)
        writePending(frames: Int(ready - base))
    }

    private func writePending(frames: Int) {
        let count = min(frames, pending[0].count)
        guard count > 0, let file, let base = pendingStart else { return }
        var writable = count
        if let limit = frameLimit { writable = max(0, min(writable, Int(limit - framesWritten))) }
        if writable > 0, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(writable)) {
            buffer.frameLength = AVAudioFrameCount(writable)
            for ch in 0..<channels {
                let out = buffer.floatChannelData![ch]
                pending[ch].withUnsafeBufferPointer { out.update(from: $0.baseAddress!, count: writable) }
                // Integer files cannot hold samples beyond full scale: clip them and count it.
                // Float files keep the headroom untouched.
                if !format.isFloat { clippedSamples += clip(out, count: writable) }
            }
            do {
                try file.write(from: buffer)
                framesWritten += AVAudioFramePosition(writable)
            } catch {
                onFatalError?(.writeFailed(error))
            }
        }
        for ch in 0..<channels { pending[ch].removeFirst(count) }
        pendingStart = base + Int64(count)
    }

    private func clip(_ samples: UnsafeMutablePointer<Float>, count: Int) -> Int {
        var over = 0
        for i in 0..<count where abs(samples[i]) > 1 { over += 1 }
        if over > 0 {
            var low: Float = -1, high: Float = 1
            vDSP_vclip(samples, 1, &low, &high, samples, 1, vDSP_Length(count))
        }
        return over
    }

    /// Writes what is left and finalizes the WAV header. Must be called on `queue`.
    func close() {
        writePending(frames: pending[0].count)
        file?.close()
        file = nil
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onFatalError?(.streamStopped(error))
    }
}

// MARK: - Session

struct CaptureResult {
    let url: URL
    let frames: AVAudioFramePosition
    let clippedSamples: Int
    var seconds: Double { Double(frames) / sampleRate }
}

/// A running capture: one SCStream feeding one Recorder.
final class CaptureSession: @unchecked Sendable {
    let url: URL
    let recorder: Recorder
    let capturedApps: [SCRunningApplication]
    private let stream: SCStream

    private init(url: URL, recorder: Recorder, stream: SCStream, capturedApps: [SCRunningApplication]) {
        self.url = url
        self.recorder = recorder
        self.stream = stream
        self.capturedApps = capturedApps
    }

    /// Checks permissions, then starts recording to `url` (replacing any file there).
    /// `onFatalError` is called on the audio queue if capture or writing fails later.
    static func start(url: URL, options: CaptureOptions, onFatalError: @escaping (CaptureError) -> Void) async throws -> CaptureSession {
        // Never wait on a permission dialog: check first; the request call only
        // registers the process in the Settings list.
        guard hasScreenCapturePermission() else {
            _ = CGRequestScreenCaptureAccess()
            throw CaptureError.screenPermissionDenied
        }
        if options.source.includesMic, !(await requestMicAccess()) { throw CaptureError.micPermissionDenied }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first else { throw CaptureError.noDisplay }

            var apps: [SCRunningApplication] = []
            let filter: SCContentFilter
            if let bundleID = options.appBundleID, options.source.includesSystem {
                // Match the app and its helper processes (e.g. com.google.Chrome.helper).
                apps = content.applications.filter {
                    $0.bundleIdentifier == bundleID || $0.bundleIdentifier.hasPrefix(bundleID + ".")
                }
                guard !apps.isEmpty else { throw CaptureError.appNotRunning(bundleID) }
                filter = SCContentFilter(display: display, including: apps, exceptingWindows: [])
            } else {
                filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            }

            let config = SCStreamConfiguration()
            config.capturesAudio = options.source.includesSystem
            config.excludesCurrentProcessAudio = true
            config.sampleRate = Int(sampleRate)
            config.channelCount = channels
            if options.source.includesMic {
                config.captureMicrophone = true
                config.microphoneCaptureDeviceID = options.micDeviceID
            }
            // Video is mandatory for an SCStream; keep it as cheap as possible.
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 3600, timescale: 1)
            config.queueDepth = 3
            config.showsCursor = false

            var tracks: [Track] = []
            if options.source.includesSystem { tracks.append(.system) }
            if options.source.includesMic { tracks.append(.mic) }

            try? FileManager.default.removeItem(at: url)
            let recorder = try Recorder(url: url, format: options.format, tracks: tracks, duration: options.duration)
            recorder.onFatalError = onFatalError
            let stream = SCStream(filter: filter, configuration: config, delegate: recorder)
            if options.source.includesSystem {
                try stream.addStreamOutput(recorder, type: .audio, sampleHandlerQueue: recorder.queue)
            }
            if options.source.includesMic {
                try stream.addStreamOutput(recorder, type: .microphone, sampleHandlerQueue: recorder.queue)
            }
            // A screen output with a throwaway queue avoids "stream output not found" log spam.
            try stream.addStreamOutput(recorder, type: .screen, sampleHandlerQueue: DispatchQueue(label: "sysaudio-record.video", qos: .background))
            try await stream.startCapture()
            return CaptureSession(url: url, recorder: recorder, stream: stream, capturedApps: apps)
        } catch let error as CaptureError {
            throw error
        } catch {
            throw isPermissionError(error) ? CaptureError.screenPermissionDenied : CaptureError.startFailed(error)
        }
    }

    /// Stops capture and finalizes the WAV file.
    func stop() async -> CaptureResult {
        try? await stream.stopCapture()
        let recorder = recorder
        return await withCheckedContinuation { continuation in
            recorder.queue.async {
                recorder.close()
                continuation.resume(returning: CaptureResult(url: self.url, frames: recorder.framesWritten, clippedSamples: recorder.clippedSamples))
            }
        }
    }
}
