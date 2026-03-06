import Foundation
import Observation

@Observable
@MainActor
final class TranscriptionService {
    private(set) var isModelLoaded = false
    private(set) var isTranscribing = false
    private(set) var currentText = ""
    private(set) var segments: [TranscriptionSegment] = []

    // FluidAudio integration will be added when SPM dependency is resolved
    // private var streamingManager: StreamingAsrManager?

    func loadModel() async throws {
        // TODO: Initialize FluidAudio StreamingAsrManager
        // Downloads model on first launch (~600MB)
        isModelLoaded = true
    }

    func startTranscription() {
        guard isModelLoaded else { return }
        isTranscribing = true
        currentText = ""
        segments = []
    }

    func processAudioBuffer(_ buffer: Any) {
        // TODO: Feed buffer to FluidAudio StreamingAsrManager
        // On each recognized segment:
        // 1. Create TranscriptionSegment
        // 2. Append to segments
        // 3. Update currentText
        // 4. Trigger OutputService to paste
    }

    func stopTranscription() -> String {
        isTranscribing = false
        let fullText = segments.map(\.text).joined(separator: " ")
        return fullText
    }
}
