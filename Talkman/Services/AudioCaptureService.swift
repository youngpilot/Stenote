import AVFoundation
import Observation

@Observable
@MainActor
final class AudioCaptureService {
    private var audioEngine: AVAudioEngine?
    private(set) var isCapturing = false
    private(set) var audioLevel: Float = 0

    private var audioBufferCallback: ((AVAudioPCMBuffer) -> Void)?

    func startCapture(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Target format: 16kHz mono for Parakeet
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.formatError
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioCaptureError.converterError
        }

        audioBufferCallback = onBuffer

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            // Update audio level for UI
            let level = buffer.floatChannelData?[0].pointee ?? 0
            Task { @MainActor in
                self.audioLevel = abs(level)
            }

            // Convert to 16kHz mono
            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * targetFormat.sampleRate / inputFormat.sampleRate
            )
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: frameCapacity
            ) else { return }

            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if error == nil {
                onBuffer(convertedBuffer)
            }
        }

        engine.prepare()
        try engine.start()
        audioEngine = engine
        isCapturing = true
    }

    func stopCapture() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isCapturing = false
        audioLevel = 0
    }
}

enum AudioCaptureError: Error, LocalizedError {
    case formatError
    case converterError

    var errorDescription: String? {
        switch self {
        case .formatError: "Failed to create audio format"
        case .converterError: "Failed to create audio converter"
        }
    }
}
