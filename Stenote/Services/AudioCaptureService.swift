import AVFoundation
import Accelerate
import os

private let logger = Logger(subsystem: "com.youngpilot.Stenote", category: "AudioCapture")

/// Captures microphone audio as 16 kHz mono for the ASR.
///
/// The `AVAudioEngine` is created once and reused for the app's lifetime: it's
/// warmed up ahead of time so the first start is fast and every later start is
/// near-instant. The mic is only live between `startCapture()` and
/// `stopCapture()` — there is no always-on microphone (or always-on indicator).
final class AudioCaptureService: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    private var converter: AVAudioConverter?
    private var tapFormat: AVAudioFormat?
    private var active = false

    // Per-recording sinks; the tap forwards to them only while `active`.
    private var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?
    private var onLevel: (@Sendable (Float) -> Void)?
    private var onSamples: (@Sendable ([Float]) -> Void)?

    /// Allocate engine resources ahead of time (no mic I/O, no indicator) so the
    /// first real start is fast. Call once at launch, only when mic is granted.
    func prepareEngine() {
        refreshTapIfNeeded()
        engine.prepare()
        logger.debug("Engine prepared")
    }

    /// Begin forwarding mic audio to the sinks. Fast on a warm engine. Throws
    /// `microphoneDenied` so the caller can surface the warning card.
    func startCapture(
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onLevel: @escaping @Sendable (Float) -> Void,
        onSamples: @escaping @Sendable ([Float]) -> Void
    ) throws {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        logger.debug("Mic permission status: \(status.rawValue, privacy: .public)")
        if status == .denied || status == .restricted { throw AudioCaptureError.microphoneDenied }
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                logger.debug("Mic permission granted: \(granted, privacy: .public)")
            }
            throw AudioCaptureError.microphoneDenied
        }

        self.onBuffer = onBuffer
        self.onLevel = onLevel
        self.onSamples = onSamples

        refreshTapIfNeeded()
        // Clear any resampler filter state left over from a previous session so
        // each recording starts clean. Safe here (unlike in stopCapture): the
        // engine is stopped and the tap is inactive, so no render-thread callback
        // can be touching the converter concurrently.
        converter?.reset()
        active = true
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    func stopCapture() {
        active = false
        if engine.isRunning { engine.stop() }   // mic off; engine kept warm for next time
    }

    /// (Re)install the tap if it's missing or the input format changed since last
    /// time (e.g. the user switched audio device between recordings). Only ever
    /// called while stopped/starting — never mid-recording.
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
        let frameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * targetFormat.sampleRate / inputFormat.sampleRate)
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else { return }

        var error: NSError?
        conv.convert(to: converted, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        guard error == nil else { return }

        if let floatData = converted.floatChannelData {
            let count = Int(converted.frameLength)
            if count > 0 {
                var rms: Float = 0
                vDSP_rmsqv(floatData[0], 1, &rms, vDSP_Length(count))
                // dB-like scale tuned for laptop mic speech.
                let db = 20 * log10(max(rms, 1e-6))
                let level = min(max((db + 55) / 40, 0), 1.0) // -55dB floor, -15dB ceiling
                onLevel?(level)
                onSamples?(Array(UnsafeBufferPointer(start: floatData[0], count: count)))
            }
        }
        onBuffer?(converted)
    }
}

enum AudioCaptureError: Error, LocalizedError {
    case microphoneDenied
    case formatError
    case converterError

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "Microphone access is denied"
        case .formatError: "Failed to create audio format"
        case .converterError: "Failed to create audio converter"
        }
    }
}
