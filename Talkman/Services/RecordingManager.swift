import AppKit
import AVFoundation
import Foundation
import Observation
import os

private let logger = Logger(subsystem: "com.youngpilot.Talkman", category: "RecordingManager")

@Observable
@MainActor
final class RecordingManager {
    static let shared = RecordingManager()

    private let audioCaptureService = AudioCaptureService()
    private let transcriptionService = TranscriptionService()
    private let outputService = OutputService()
    private let hotkeyService = HotkeyService()
    private let systemAudio = SystemAudioService.shared
    let historyService = HistoryService.shared

    private(set) var isRecording = false
    private(set) var isModelLoading = false
    private(set) var modelLoadError: String?
    private(set) var audioLevel: Float = 0.0
    private(set) var needsAccessibility = false

    var currentText: String { transcriptionService.currentText }
    var isModelLoaded: Bool { transcriptionService.isModelLoaded }
    var modelLoadingStep: String { transcriptionService.modelLoadingStep }
    var detectedLanguage: String { transcriptionService.detectedLanguage }

    private init() {
        hotkeyService.onToggle = { [weak self] in
            self?.toggle()
        }

        // Wire segment callback → incremental text insertion
        // Called directly (no Task wrapper) to ensure text is inserted
        // before stopRecording() calls endSession()
        transcriptionService.onSegmentReady = { [weak self] text in
            self?.outputService.insertText(text + " ")
        }

        // Wire silence timeout → auto-stop
        transcriptionService.onSilenceTimeout = { [weak self] in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                logger.info("Auto-stopping recording due to silence timeout")
                await self.stopRecording()
                SoundFeedback.playStop()
            }
        }
    }

    func setup() async {
        logger.info("Setup starting — registering hotkey")
        hotkeyService.start()
        outputService.startTrackingAppActivations()
        needsAccessibility = !AXIsProcessTrusted()
        isModelLoading = true
        modelLoadError = nil
        do {
            logger.info("Loading models...")
            try await transcriptionService.loadModel()
            logger.info("Models loaded successfully")
        } catch {
            modelLoadError = error.localizedDescription
            logger.error("Failed to load model: \(error.localizedDescription)")
        }
        isModelLoading = false
    }

    func toggle() {
        if isRecording {
            Task { await stopRecording() }
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard !isRecording, transcriptionService.isModelLoaded else { return }

        outputService.rememberSourceApp()

        Task { @MainActor in
            await transcriptionService.startTranscription()
            self.beginCapture()
        }
    }

    private func beginCapture() {
        guard !isRecording else { return }

        do {
            try audioCaptureService.startCapture(
                onBuffer: { [weak self] buffer in
                    nonisolated(unsafe) let sendableBuffer = buffer
                    Task { @MainActor in
                        guard let self else { return }
                        await self.transcriptionService.processAudioBuffer(sendableBuffer)
                    }
                },
                onLevel: { [weak self] level in
                    Task { @MainActor in
                        self?.audioLevel = level
                    }
                }
            )
            isRecording = true
            needsAccessibility = !AXIsProcessTrusted()
            SoundFeedback.playStart()

            switch SettingsStore.shared.mediaPlaybackOption {
            case .stopMedia:
                systemAudio.fadeOutAndPause(stopMedia: true)
            case .muteOnly:
                systemAudio.fadeOutAndPause(stopMedia: false)
            case .none:
                break
            }

            // Paste prefix text if configured
            let prefix = SettingsStore.shared.prefixText
            if !prefix.isEmpty {
                outputService.insertText(prefix + " ")
            }
        } catch {
            logger.error("Failed to start capture: \(error.localizedDescription)")
        }
    }

    func stopRecording() async {
        guard isRecording else { return }
        audioCaptureService.stopCapture()
        isRecording = false
        audioLevel = 0.0
        if SettingsStore.shared.mediaPlaybackOption != .none {
            systemAudio.resumeAndFadeIn()
        }
        SoundFeedback.playStop()

        // Transcribe remaining audio — the onSegmentReady callback wraps in
        // Task { @MainActor }, so we must yield to let those tasks run before
        // ending the session.
        let finalText = await transcriptionService.stopTranscription()

        // Append suffix text if configured
        let suffix = SettingsStore.shared.suffixText
        if !suffix.isEmpty, !finalText.isEmpty {
            outputService.insertText(" " + suffix)
        }

        // Save to history
        if !finalText.isEmpty {
            let prefix = SettingsStore.shared.prefixText
            var historyText = finalText
            if !prefix.isEmpty { historyText = prefix + " " + historyText }
            if !suffix.isEmpty { historyText += " " + suffix }
            historyService.addEntry(historyText)
        }

        // Wait for all pending pastes to complete before ending session.
        // doPaste uses async DispatchQueue drains (scheduleDrain +20ms, activate +60ms)
        // so isPasting stays true until the full chain completes.
        for _ in 0..<20 {
            if !outputService.hasPendingOutput { break }
            outputService.flushPendingText()
            try? await Task.sleep(for: .milliseconds(10))
        }

        outputService.endSession()
    }
}

// MARK: - Sound Feedback

enum SoundFeedback {
    static func playStart() {
        NSSound(named: "Tink")?.play()
    }

    static func playStop() {
        NSSound(named: "Bottle")?.play()
    }
}
