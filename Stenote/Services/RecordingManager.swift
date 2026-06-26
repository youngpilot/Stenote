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
    private(set) var isStarting = false   // shortcut registered, engine spinning up (yellow)
    private(set) var isModelLoading = false
    private(set) var modelLoadError: String?
    private(set) var audioLevel: Float = 0.0
    private(set) var waveformSamples: [Float] = []
    private(set) var needsAccessibility = false
    private(set) var needsMicrophone = false
    private(set) var isTranscribingFile = false
    private(set) var fileTranscriptionName: String?
    private(set) var fileTranscriptionError: String?
    private var recordingStartTime: Date?
    private var startTask: Task<Void, Never>?
    private var audioContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    /// Set when stop is pressed during the brief "starting" window. A half-started
    /// ASR can't be torn down cleanly mid-flight, so we let it come up and then
    /// stop it cleanly (honored in beginCapture).
    private var stopAfterStart = false
    private var sampleRingBuffer = RingBuffer<Float>(capacity: 16000 * 3, defaultValue: 0)

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
        guard !isRecording, !isStarting, transcriptionService.isModelLoaded else { return }

        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .denied || micStatus == .restricted {
            needsMicrophone = true
            return
        }

        // Instant acknowledgement the moment the shortcut registers — yellow icon
        // + start sound — BEFORE the audio engine spins up (~200ms HAL setup).
        stopAfterStart = false
        isStarting = true
        needsMicrophone = false
        SoundFeedback.playStart()

        outputService.rememberSourceApp()
        transcriptionService.beginCapturing()   // hold audio until ASR is ready
        startTask = Task { @MainActor in await transcriptionService.startTranscription() }

        // Defer the engine start so the "starting" state paints first; audio
        // captured once it's up is buffered (no lost words).
        DispatchQueue.main.async { [weak self] in self?.beginCapture() }
    }

    private func beginCapture() {
        guard isStarting, !isRecording else { return }

        // Single ordered audio path: the tap yields into one stream that one
        // serial consumer drains in capture order (no per-buffer Tasks, no race).
        let continuation = transcriptionService.startAudioPipeline()
        audioContinuation = continuation
        do {
            try audioCaptureService.startCapture(
                onBuffer: { buffer in
                    nonisolated(unsafe) let b = buffer
                    continuation.yield(b)
                },
                onLevel: { [weak self] level in
                    Task { @MainActor in
                        self?.audioLevel = level
                    }
                },
                onSamples: { [weak self] samples in
                    Task { @MainActor in
                        guard let self else { return }
                        self.sampleRingBuffer.append(contentsOf: samples)
                        self.waveformSamples = self.sampleRingBuffer.toArray()
                    }
                }
            )
            isStarting = false
            isRecording = true
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
        } catch {
            isStarting = false
            stopAfterStart = false
            if case AudioCaptureError.microphoneDenied = error {
                let status = AVCaptureDevice.authorizationStatus(for: .audio)
                needsMicrophone = (status == .denied || status == .restricted)
            }
            logger.error("Failed to start capture: \(error.localizedDescription)")
        }
    }

    func stopRecording() async {
        guard isRecording else { return }
        audioCaptureService.stopCapture()
        isRecording = false
        audioLevel = 0.0
        waveformSamples = []
        sampleRingBuffer = RingBuffer<Float>(capacity: 16000 * 3, defaultValue: 0)
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

        let finalText = await transcriptionService.stopTranscription()

        // Paste the COMPLETE transcript (with prefix/suffix) once — reliable,
        // with no chunk-boundary artifacts from incremental pasting.
        var output = finalText
        if !output.isEmpty {
            let prefix = SettingsStore.shared.prefixText
            let suffix = SettingsStore.shared.suffixText
            if !prefix.isEmpty { output = prefix + " " + output }
            if !suffix.isEmpty { output = output + " " + suffix }

            outputService.insertText(output)
            let duration = recordingStartTime.map { Date().timeIntervalSince($0) }
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
        fileTranscriptionError = nil
        isTranscribingFile = true
        fileTranscriptionName = url.lastPathComponent
        Task { @MainActor in
            defer { isTranscribingFile = false; fileTranscriptionName = nil }
            do {
                let text = try await transcriptionService.transcribeFile(url: url)
                guard !text.isEmpty else {
                    fileTranscriptionError = "No speech found in that file."
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                historyService.addEntry(text)
                SoundFeedback.playStop()
            } catch {
                fileTranscriptionError = error.localizedDescription
                logger.error("File transcription failed: \(error.localizedDescription)")
            }
        }
    }

    /// Transcribe an audio file currently on the clipboard (a copied file), if any.
    func transcribeAudioFromClipboard() {
        guard let url = Self.audioFileURLOnPasteboard() else {
            fileTranscriptionError = "No audio file on the clipboard."
            return
        }
        transcribeFile(url)
    }

    /// The first audio file URL on the general pasteboard, if any.
    static func audioFileURLOnPasteboard() -> URL? {
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        return urls.first { url in
            (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.conforms(to: .audio) ?? false
        }
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
