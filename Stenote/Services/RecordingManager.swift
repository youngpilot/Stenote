import AppKit
import AVFoundation
import Foundation
import Observation
import os
import UniformTypeIdentifiers

private let logger = Logger(subsystem: "com.youngpilot.Stenote", category: "RecordingManager")

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
    private(set) var isStarting = false   // shortcut registered, engine spinning up (shows red)
    private(set) var isModelLoading = false
    private(set) var modelLoadError: String?
    private(set) var inputLevel: Float = 0.0   // smoothed mic level [0,1] for the meter
    private(set) var needsAccessibility = false
    private(set) var needsMicrophone = false
    private(set) var isTranscribingFile = false
    private(set) var fileTranscriptionName: String?
    /// A file transcription finished and is waiting to be seen — drives the green
    /// menubar badge. Cleared when the popover opens (or a new activity starts).
    private(set) var fileTranscriptionDone = false
    private(set) var statusMessage: StatusMessage?
    private var statusClearTask: Task<Void, Never>?
    private var recordingStartTime: Date?
    private var startTask: Task<Void, Never>?
    private var audioContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    /// Set when stop is pressed during the brief "starting" window. A half-started
    /// ASR can't be torn down cleanly mid-flight, so we let it come up and then
    /// stop it cleanly (honored in beginCapture).
    private var stopAfterStart = false

    var currentText: String { transcriptionService.currentText }
    var isModelLoaded: Bool { transcriptionService.isModelLoaded }
    var modelLoadingStep: String { transcriptionService.modelLoadingStep }
    var detectedLanguage: String { transcriptionService.detectedLanguage }
    var lastConfidence: Float { transcriptionService.lastConfidence }
    var minTokenConfidence: Float { transcriptionService.minTokenConfidence }
    var avgTokenConfidence: Float { transcriptionService.avgTokenConfidence }
    var isVocabModelLoading: Bool { transcriptionService.isVocabModelLoading }
    var vocabModelLoadFailed: Bool { transcriptionService.vocabModelLoadFailed }

    /// Preload the CTC vocabulary model when the user enables Model Boosting,
    /// so it's ready before the next recording.
    func prepareVocabularyBoosting() {
        Task { await transcriptionService.ensureVocabModelsLoaded() }
    }

    private init() {
        hotkeyService.onToggle = { [weak self] in
            self?.toggle()
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
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        needsMicrophone = (micStatus == .denied || micStatus == .restricted)
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

        // Decode the feedback sounds up front so the first start/stop chirp has
        // no load latency.
        SoundFeedback.preload()

        // Warm up the audio engine so the first recording starts fast — only if
        // the mic is already granted, so we never touch it prematurely.
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            audioCaptureService.prepareEngine()
        }

        // Daily update check (no-op in Manual mode; connectivity-driven, at most
        // one GET per 24h). Touching the singleton also starts its net monitor.
        UpdateService.shared.maybeAutoCheck()
    }

    func toggle() {
        if isRecording {
            Task { await stopRecording() }
        } else if isStarting {
            // Stop pressed during the ~200ms start window — honor it the instant
            // the recording is actually live (beginCapture checks this flag).
            stopAfterStart = true
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard !isRecording, !isStarting else { return }
        // Instant feedback instead of a silent no-op while the speech model is
        // still loading (e.g. right after launch) — otherwise a press feels ignored.
        guard transcriptionService.isModelLoaded else {
            showStatus("Loading speech model…")
            return
        }

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .denied || micStatus == .restricted {
            needsMicrophone = true
            return
        }

        // Instant acknowledgement the moment the shortcut registers — red icon
        // + start sound — BEFORE the audio engine spins up (~200ms HAL setup).
        stopAfterStart = false
        fileTranscriptionDone = false   // a new recording supersedes a stale "ready" badge
        isStarting = true
        needsMicrophone = false
        SoundFeedback.playStart()

        // If cleanup is enabled, warm the on-device model now so it's ready (fast)
        // by the time recording stops.
        if SettingsStore.shared.cleanupText { TextCleanupService.shared.prewarm() }

        outputService.rememberSourceApp()
        transcriptionService.beginCapturing()   // hold audio until ASR is ready
        startTask = Task { @MainActor in await transcriptionService.startTranscription() }

        // beginCapture starts the engine off-main on a dedicated queue and returns
        // immediately; we flip to red only once the mic is actually live.
        beginCapture()
    }

    private func beginCapture() {
        guard isStarting, !isRecording else { return }

        // Single ordered audio path: the tap yields into one stream that one
        // serial consumer drains in capture order (no per-buffer Tasks, no race).
        // Single ordered audio path: the tap yields into one stream that one
        // serial consumer drains in capture order (no per-buffer Tasks, no race).
        let continuation = transcriptionService.startAudioPipeline()
        audioContinuation = continuation
        // Engine start runs on AudioCaptureService's dedicated serial queue (off
        // main, but ONE thread for all engine ops → safe). We enter the recording
        // state — and turn the icon red — only once the engine is actually live, so
        // "red == recording" with no lost first words.
        audioCaptureService.startCapture(
            onBuffer: { buffer in
                nonisolated(unsafe) let b = buffer
                continuation.yield(b)
            },
            onLevel: { [weak self] level in
                Task { @MainActor in
                    // Ignore callbacks enqueued before stop so a late one can't
                    // overwrite the inputLevel reset.
                    guard let self, self.isRecording else { return }
                    // Asymmetric ballistics: fast attack, slow release.
                    let alpha: Float = level > self.inputLevel ? 0.6 : 0.2
                    self.inputLevel += alpha * (level - self.inputLevel)
                }
            },
            completion: { [weak self] error in
                Task { @MainActor in self?.captureCompleted(error) }
            }
        )
    }

    /// Called on the main actor once the audio engine reports a result.
    private func captureCompleted(_ error: AudioCaptureError?) {
        if let error { captureFailed(error); return }
        // Torn down during start-up (stop pressed, etc.) — stop the engine that
        // just went live instead of entering the recording state.
        guard isStarting, !isRecording else {
            audioCaptureService.stopCapture()
            audioContinuation?.finish()
            audioContinuation = nil
            return
        }

        isStarting = false
        isRecording = true   // RED == recording — only now that the mic is live
        recordingStartTime = Date()
        needsAccessibility = !AXIsProcessTrusted()

        // Stop was pressed during startup — bring it down cleanly now (before
        // muting media, so there's no audible blip).
        if stopAfterStart {
            stopAfterStart = false
            Task { await stopRecording() }
            return
        }

        if SettingsStore.shared.silenceMediaWhileRecording {
            systemAudio.muteOutput()
        }
        if SettingsStore.shared.pauseMediaApps {
            systemAudio.pauseMediaApps()
        }
        // Prefix/suffix are pasted together with the full text when recording stops.
    }

    private func captureFailed(_ error: AudioCaptureError) {
        isStarting = false
        stopAfterStart = false
        audioCaptureService.stopCapture()
        audioContinuation?.finish()
        audioContinuation = nil
        if error == .microphoneDenied {
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            needsMicrophone = (status == .denied || status == .restricted)
        }
        logger.error("Capture failed: \(error.localizedDescription)")
    }

    func stopRecording() async {
        guard isRecording else { return }
        audioCaptureService.stopCapture()
        isRecording = false
        inputLevel = 0.0
        // Always restore — each is a no-op if it wasn't applied (also handles a
        // setting being toggled off mid-recording).
        systemAudio.restoreOutput()
        systemAudio.resumeMediaApps()
        SoundFeedback.playStop()

        // Ensure the ASR finished starting before we feed the tail / finish.
        await startTask?.value
        startTask = nil

        // Close the ordered audio pipeline and wait for the lone consumer to
        // feed every remaining buffer (in capture order) into the ASR before we
        // finish — deterministic, no fixed-timeout drain.
        audioContinuation?.finish()
        audioContinuation = nil
        await transcriptionService.awaitAudioConsumer()

        var finalText = await transcriptionService.stopTranscription()
        // Capture duration BEFORE optional cleanup so WPM reflects speaking time,
        // not the cleanup pass.
        let duration = recordingStartTime.map { Date().timeIntervalSince($0) }

        // Optional on-device AI cleanup (punctuation, capitalization, filler-word
        // removal). Opt-in; runs locally, text never leaves the Mac; falls back to
        // the original text on any failure.
        if SettingsStore.shared.cleanupText, !finalText.isEmpty {
            showStatus("Cleaning up…")
            finalText = await TextCleanupService.shared.cleanup(finalText)
        }

        // Paste the COMPLETE transcript (with prefix/suffix) once — reliable,
        // with no chunk-boundary artifacts from incremental pasting.
        var output = finalText
        if !output.isEmpty {
            let prefix = SettingsStore.shared.prefixText
            let suffix = SettingsStore.shared.suffixText
            if !prefix.isEmpty { output = prefix + " " + output }
            if !suffix.isEmpty { output = output + " " + suffix }

            outputService.insertText(output)
            historyService.addEntry(output, duration: duration)
        }

        // Wait for all pending pastes to complete before ending session.
        // doPaste uses async DispatchQueue drains (scheduleDrain +20ms, activate +60ms)
        // so isPasting stays true until the full chain completes.
        for i in 0..<30 {
            if !outputService.hasPendingOutput { break }
            outputService.flushPendingText()
            try? await Task.sleep(for: .milliseconds(10))
            if i == 29 {
                logger.warning("Paste drain timeout — ending session anyway")
            }
        }

        // If Accessibility is off we couldn't type anywhere — leave the transcript
        // on the clipboard so the user can paste it, and keep it there (don't restore).
        if !output.isEmpty, !AXIsProcessTrusted() {
            outputService.suppressClipboardRestore = true
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(output, forType: .string)
        }

        outputService.endSession()
    }

    // MARK: - File transcription

    /// Transcribe an audio file (drag-drop / picker / clipboard) with the batch
    /// engine. A file has no source app to type into, so the result is copied to
    /// the clipboard and saved to History (no auto-typing). Disabled while a live
    /// recording is in flight.
    func transcribeFile(_ url: URL) {
        guard !isRecording, !isStarting, !isTranscribingFile,
              transcriptionService.isModelLoaded else { return }
        statusMessage = nil
        fileTranscriptionDone = false
        isTranscribingFile = true
        fileTranscriptionName = url.lastPathComponent
        Task { @MainActor in
            defer { isTranscribingFile = false; fileTranscriptionName = nil }
            do {
                let text = try await transcriptionService.transcribeFile(url: url)
                guard !text.isEmpty else {
                    showStatus("No speech found in that file.", isError: true)
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                historyService.addEntry(text)
                SoundFeedback.playStop()
                showStatus("Saved to history · copied")
                fileTranscriptionDone = true   // green menubar badge until the popover is opened
            } catch {
                showStatus(error.localizedDescription, isError: true)
                logger.error("File transcription failed: \(error.localizedDescription)")
            }
        }
    }

    /// Transcribe an audio file currently on the clipboard (a copied file), if any.
    func transcribeAudioFromClipboard() {
        guard let url = Self.audioFileURLOnPasteboard() else {
            showStatus("No audio file on the clipboard.", isError: true)
            return
        }
        transcribeFile(url)
    }

    /// Called when the popover opens — clears the green "transcription ready"
    /// menubar badge (the user has come to look).
    func markWindowOpened() {
        fileTranscriptionDone = false
    }

    /// Show a transient one-line status (auto-dismissed). Errors linger a little
    /// longer so they can be read. One line, no queue — replaces any prior message.
    func showStatus(_ text: String, isError: Bool = false) {
        statusMessage = StatusMessage(text: text, isError: isError)
        statusClearTask?.cancel()
        statusClearTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(isError ? 4.0 : 2.5))
            guard !Task.isCancelled else { return }
            statusMessage = nil
        }
    }

    /// The first audio file URL on the general pasteboard, if any.
    static func audioFileURLOnPasteboard() -> URL? {
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        return urls.first { url in
            (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.conforms(to: .audio) ?? false
        }
    }

}

/// A transient, auto-dismissed status line shown in the popover.
struct StatusMessage: Equatable {
    let text: String
    let isError: Bool
}

// MARK: - Sound Feedback

@MainActor
enum SoundFeedback {
    // Cache + reuse the NSSound instances so the first chirp has no decode
    // latency and a press never waits on a fresh named-sound lookup.
    private static let startSound = NSSound(named: "Tink")
    private static let stopSound = NSSound(named: "Bottle")

    static func playStart() { restart(startSound) }
    static func playStop() { restart(stopSound) }

    /// Force the sounds to decode up front (call once at launch).
    static func preload() { _ = startSound; _ = stopSound }

    private static func restart(_ sound: NSSound?) {
        guard let sound else { return }
        if sound.isPlaying { sound.stop() }   // allow rapid re-trigger
        sound.play()
    }
}
