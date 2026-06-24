import AVFoundation
import Accelerate
import os

private let logger = Logger(subsystem: "com.youngpilot.Stenote", category: "AudioCapture")

final class AudioCaptureService: @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var configObserver: NSObjectProtocol?

    // Stored so we can rebuild the tap when the input device/format changes.
    private var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?
    private var onLevel: (@Sendable (Float) -> Void)?
    private var onSamples: (@Sendable ([Float]) -> Void)?

    func startCapture(
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onLevel: @escaping @Sendable (Float) -> Void,
        onSamples: @escaping @Sendable ([Float]) -> Void
    ) throws {
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        logger.debug("Mic permission status: \(micStatus.rawValue, privacy: .public)")
        switch micStatus {
        case .denied, .restricted:
            throw AudioCaptureError.microphoneDenied
        case .notDetermined:
            // First use: kick off the prompt, but don't capture silence this round —
            // the caller surfaces "grant microphone" and the next press will work.
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                logger.debug("Mic permission granted: \(granted, privacy: .public)")
            }
            throw AudioCaptureError.microphoneDenied
        default:
            break
        }

        self.onBuffer = onBuffer
        self.onLevel = onLevel
        self.onSamples = onSamples

        let engine = AVAudioEngine()
        audioEngine = engine
        try installTap(on: engine)
        engine.prepare()
        try engine.start()

        // Rebuild the tap when the input device changes mid-recording (AirPods
        // unplugged, interface docked) — otherwise capture silently dies.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    private func installTap(on engine: AVAudioEngine) throws {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        logger.debug("Input format: \(inputFormat.description, privacy: .public)")

        // Target format: 16kHz mono for Parakeet
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false
        ) else { throw AudioCaptureError.formatError }

        guard let conv = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioCaptureError.converterError
        }
        converter = conv

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer, with: conv, inputFormat: inputFormat, targetFormat: targetFormat)
        }
    }

    private func handleConfigurationChange() {
        guard let engine = audioEngine else { return }
        logger.info("Audio engine configuration changed — rebuilding tap")
        engine.inputNode.removeTap(onBus: 0)
        do {
            try installTap(on: engine)
            if !engine.isRunning { try engine.start() }
        } catch {
            logger.error("Failed to rebuild tap after device change: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func process(
        _ buffer: AVAudioPCMBuffer, with conv: AVAudioConverter,
        inputFormat: AVAudioFormat, targetFormat: AVAudioFormat
    ) {
        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let frameCapacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard frameCapacity > 0,
              let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity)
        else { return }

        var error: NSError?
        var fed = false
        conv.convert(to: convertedBuffer, error: &error) { _, outStatus in
            // Feed this tap buffer exactly once per convert() call.
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error {
            logger.debug("Audio conversion error: \(error.localizedDescription, privacy: .public)")
            return
        }

        if let floatData = convertedBuffer.floatChannelData {
            let count = Int(convertedBuffer.frameLength)
            if count > 0 {
                var rms: Float = 0
                vDSP_rmsqv(floatData[0], 1, &rms, vDSP_Length(count))
                // dB-like scale tuned for laptop mic speech:
                // silence → 0, quiet → 0.4, normal → 0.7, loud → 1.0
                let db = 20 * log10(max(rms, 1e-6))
                let level = min(max((db + 55) / 40, 0), 1.0) // -55dB floor, -15dB ceiling
                onLevel?(level)
                onSamples?(Array(UnsafeBufferPointer(start: floatData[0], count: count)))
            }
        }
        onBuffer?(convertedBuffer)
    }

    func stopCapture() {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        converter = nil
        onBuffer = nil
        onLevel = nil
        onSamples = nil
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
