import Foundation
import Observation

@Observable
@MainActor
final class RecordingManager {
    static let shared = RecordingManager()

    private let audioCaptureService = AudioCaptureService()
    private let transcriptionService = TranscriptionService()
    private let outputService = OutputService()
    private let hotkeyService = HotkeyService()

    private(set) var isRecording = false
    var currentText: String { transcriptionService.currentText }
    var isModelLoaded: Bool { transcriptionService.isModelLoaded }

    private init() {
        hotkeyService.onToggle = { [weak self] in
            self?.toggle()
        }
    }

    func setup() async {
        hotkeyService.start()
        do {
            try await transcriptionService.loadModel()
        } catch {
            print("Failed to load model: \(error)")
        }
    }

    func toggle() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard !isRecording, transcriptionService.isModelLoaded else { return }

        outputService.rememberSourceApp()
        transcriptionService.startTranscription()

        do {
            try audioCaptureService.startCapture { [weak self] buffer in
                self?.transcriptionService.processAudioBuffer(buffer)
            }
            isRecording = true
        } catch {
            print("Failed to start capture: \(error)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        audioCaptureService.stopCapture()
        let finalText = transcriptionService.stopTranscription()

        // Paste any remaining text
        if !finalText.isEmpty {
            outputService.pasteText(finalText)
        }

        isRecording = false
    }
}
