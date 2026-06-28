import AVFoundation
import Accelerate
import os

private let logger = Logger(subsystem: "com.youngpilot.Stenote", category: "AudioCapture")

/// Captures microphone audio as 16 kHz mono for the ASR.
///
/// The `AVAudioEngine` is created once and reused for the app's lifetime; it's
/// warmed up ahead of time so the first start is fast. The mic is only live
/// between `startCapture()` and `stopCapture()` — there is no always-on
/// microphone (or always-on indicator).
///
/// THREADING: every AVAudioEngine operation (prepare / tap install / start /
/// stop) runs on the single serial `engineQueue`. AVAudioEngine is not
/// thread-safe — mixing main-thread tap-install with a background-thread start
/// scrambles/drops the first buffers (the 55461fa regression). One queue, always.
final class AudioCaptureService: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let engineQueue = DispatchQueue(label: "com.youngpilot.Stenote.audioengine", qos: .userInitiated)
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    private var converter: AVAudioConverter?
    private var tapFormat: AVAudioFormat?
    private var active = false

    // Per-recording sinks; the tap forwards to them only while `active`.
    private var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?
    private var onLevel: (@Sendable (Float) -> Void)?

    /// Allocate engine resources ahead of time (no mic I/O, no indicator) so the
    /// first real start is fast. Call once at launch, only when mic is granted.
    func prepareEngine() {
        engineQueue.async { [self] in
            refreshTapIfNeeded()
            engine.prepare()
            logger.debug("Engine prepared")
        }
    }

    /// Begin forwarding mic audio to the sinks. All engine I/O runs on
    /// `engineQueue` (off the main thread, but always the SAME thread). The audio
    /// engine start (~HAL setup) is the only unavoidable latency before the mic is
    /// live — there's no always-on mic. `completion` reports `nil` on success
    /// (engine live → capturing) or an error; the caller hops it to the main actor
    /// and only then flips into the recording state (red == recording).
    func startCapture(
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onLevel: @escaping @Sendable (Float) -> Void,
        completion: @escaping @Sendable (AudioCaptureError?) -> Void
    ) {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        logger.debug("Mic permission status: \(status.rawValue, privacy: .public)")
        if status == .denied || status == .restricted { completion(.microphoneDenied); return }
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                logger.debug("Mic permission granted: \(granted, privacy: .public)")
            }
            completion(.microphoneDenied); return
        }

        self.onBuffer = onBuffer
        self.onLevel = onLevel

        engineQueue.async { [self] in
            do {
                refreshTapIfNeeded()
                // Clear any resampler filter state from the previous session. Safe
                // here: the engine is stopped and the tap is inactive, so no
                // render-thread callback can be touching the converter.
                converter?.reset()
                active = true
                if !engine.isRunning {
                    engine.prepare()
                    try engine.start()
                }
                completion(nil)
            } catch {
                active = false
                logger.error("Failed to start engine: \(error.localizedDescription, privacy: .public)")
                completion(.engineStartFailed)
            }
        }
    }

    func stopCapture() {
        active = false   // stop forwarding immediately (handleTap guards on this)
        engineQueue.async { [self] in
            if engine.isRunning { engine.stop() }   // mic off; engine kept warm for next time
        }
    }

    /// (Re)install the tap if it's missing or the input format changed since last
    /// time (e.g. the user switched audio device between recordings). Only ever
    /// called on `engineQueue` while stopped/starting — never mid-recording.
    private func refreshTapIfNeeded() {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { return } // no device yet
        if converter != nil, tapFormat == inputFormat { return }

        input.removeTap(onBus: 0)
        guard let conv = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            logger.error("Failed to create audio converter")
            converter = nil
            tapFormat = nil
            return
        }
        converter = conv
        tapFormat = inputFormat
        let target = targetFormat
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.handleTap(buffer, inputFormat: inputFormat, targetFormat: target)
        }
        logger.debug("Tap installed @ \(inputFormat.description, privacy: .public)")
    }

    private func handleTap(_ buffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat, targetFormat: AVAudioFormat) {
        guard active, let conv = converter else { return }
        // Generous output capacity (round up + headroom) so the resampler output is
        // never truncated.
        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let frameCapacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else { return }

        // CRITICAL: hand the resampler this input buffer EXACTLY ONCE. The old code
        // returned `buffer` on every input-block call, so when the resampler asked
        // for more input (e.g. while priming its filter) it got the SAME buffer
        // again → duplicated/garbled audio, worst at the start of a clip (so short
        // clips came out mangled like "to tst wi siht's aus"). Return .noDataNow
        // after the first hand-off; the converter keeps its filter state for the
        // next call, giving a clean, continuous stream.
        var error: NSError?
        var didProvide = false
        let status = conv.convert(to: converted, error: &error) { _, outStatus in
            if didProvide {
                outStatus.pointee = .noDataNow
                return nil
            }
            didProvide = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, converted.frameLength > 0 else { return }

        if let floatData = converted.floatChannelData, let onLevel {
            let count = Int(converted.frameLength)
            if count > 0 {
                // Emit several sub-window levels per buffer (~16/sec at 4096-frame
                // taps) so the level meter scrolls smoothly instead of in ~4 steps.
                let subWindows = 4
                let windowLen = max(1, count / subWindows)
                var offset = 0
                while offset < count {
                    let len = min(windowLen, count - offset)
                    var rms: Float = 0
                    vDSP_rmsqv(floatData[0] + offset, 1, &rms, vDSP_Length(len))
                    // dB-like scale tuned for laptop mic speech.
                    let db = 20 * log10(max(rms, 1e-6))
                    let level = min(max((db + 55) / 40, 0), 1.0) // -55dB floor, -15dB ceiling
                    onLevel(level)
                    offset += len
                }
            }
        }
        onBuffer?(converted)
    }
}

enum AudioCaptureError: Error, LocalizedError {
    case microphoneDenied
    case formatError
    case converterError
    case engineStartFailed

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "Microphone access is denied"
        case .formatError: "Failed to create audio format"
        case .converterError: "Failed to create audio converter"
        case .engineStartFailed: "Failed to start the audio engine"
        }
    }
}
