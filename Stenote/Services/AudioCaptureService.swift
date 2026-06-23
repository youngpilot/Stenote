import AVFoundation
import Accelerate

final class AudioCaptureService: @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private var converter: AVAudioConverter?

    func startCapture(
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onLevel: @escaping @Sendable (Float) -> Void,
        onSamples: @escaping @Sendable ([Float]) -> Void
    ) throws {
        // Check microphone permission
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        NSLog("[AudioCapture] Mic permission status: \(micStatus.rawValue) (0=notDetermined, 1=restricted, 2=denied, 3=authorized)")
        if micStatus == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                NSLog("[AudioCapture] Mic permission granted: \(granted)")
            }
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        NSLog("[AudioCapture] Input format: \(inputFormat)")

        // Target format: 16kHz mono for Parakeet
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.formatError
        }

        guard let conv = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioCaptureError.converterError
        }
        converter = conv

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * targetFormat.sampleRate / inputFormat.sampleRate
            )
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: frameCapacity
            ) else { return }

            var error: NSError?
            conv.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if error == nil {
                // Compute RMS level from converted buffer
                if let floatData = convertedBuffer.floatChannelData {
                    let count = Int(convertedBuffer.frameLength)
                    if count > 0 {
                        var rms: Float = 0
                        vDSP_rmsqv(floatData[0], 1, &rms, vDSP_Length(count))
                        // Convert to dB-like scale tuned for laptop mic speech
                        // Maps silence → 0, quiet speech → 0.4, normal speech → 0.7, loud → 1.0
                        let db = 20 * log10(max(rms, 1e-6))
                        let level = min(max((db + 55) / 40, 0), 1.0) // -55dB floor, -15dB ceiling
                        onLevel(level)
                        let samples = Array(UnsafeBufferPointer(start: floatData[0], count: count))
                        onSamples(samples)
                    }
                }
                onBuffer(convertedBuffer)
            }
        }

        engine.prepare()
        try engine.start()
        audioEngine = engine
    }

    func stopCapture() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        converter = nil
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
