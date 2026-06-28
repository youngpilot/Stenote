import AVFoundation
import FluidAudio
import Foundation
import NaturalLanguage
import Observation
import os

private let logger = Logger(subsystem: "com.youngpilot.Stenote", category: "Transcription")

@Observable
@MainActor
final class TranscriptionService {
    private(set) var isModelLoaded = false
    private(set) var isTranscribing = false
    private(set) var currentText = ""
    private(set) var modelLoadingStep = ""

    private let textReplacement = TextReplacementService.shared
    private let voiceCommands = VoiceCommandService.shared

    // Shared FluidAudio components
    private var asrModels: UncheckedSendableBox<AsrModels>?
    private var batchAsr: AsrManager?        // ONE batch engine: live dictation (v2) + file transcription
    private var vadManager: VadManager?
    private var ctcBox: UncheckedSendableBox<CtcModels>?

    // Lazy load state for the CTC vocabulary-boosting model (~98 MB).
    private(set) var isVocabModelLoading = false
    private(set) var vocabModelLoadFailed = false
    private var ctcLoadTask: Task<Bool, Never>?

    // --- Capture state (v2: buffer raw audio during recording, transcribe ONCE
    // at stop with the full-context batch engine — no streaming windows). This is
    // why short clips don't garble and the first words are never lost to ASR
    // warm-up: the model only runs at stop, on the complete audio.
    private var isCapturing = false                 // mic is live; buffer audio
    private var audioConsumer: Task<Void, Never>?   // lone, serial consumer of the audio stream

    // --- VAD state (auto-stop) ---
    private var vadBuffer: [Float] = []
    private var vadStreamState: VadStreamState = .initial()
    private var lastSpeechTime: Date?

    // Language detection + confidence (set from the batch result where available)
    private(set) var detectedLanguage = ""
    private(set) var lastConfidence: Float = 0
    private(set) var minTokenConfidence: Float = 0
    private(set) var avgTokenConfidence: Float = 0

    var onSilenceTimeout: (() -> Void)?

    // MARK: - Model Loading

    func loadModel() async throws {
        modelLoadingStep = "Downloading ASR model… (1/2)"
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        asrModels = UncheckedSendableBox(models)

        // One batch engine powers both live dictation (transcribe at stop) and
        // file transcription — full context, best accuracy. Initialized up front
        // so stopping a recording transcribes immediately.
        let manager = AsrManager()
        try await manager.initialize(models: models)
        batchAsr = manager

        // VAD powers auto-stop and paragraph-break detection.
        modelLoadingStep = "Loading VAD model… (2/2)"
        vadManager = try await VadManager()

        modelLoadingStep = ""
        isModelLoaded = true
    }

    // MARK: - Vocabulary Boosting (CTC model load for the settings toggle)
    //
    // NOTE (v2): boosting was applied on the old streaming path. The batch path
    // does NOT apply it yet — deterministic word REPLACEMENTS (postProcess) remain
    // the primary correction mechanism. Re-wiring CTC boosting into the batch
    // engine is a tracked follow-up; the model still loads here so the toggle's
    // download/state stays honest.

    /// Idempotently download + load the CTC model used for vocabulary boosting.
    @discardableResult
    func ensureVocabModelsLoaded() async -> Bool {
        if ctcBox != nil { return true }
        if let task = ctcLoadTask { return await task.value }

        isVocabModelLoading = true
        vocabModelLoadFailed = false
        let task = Task { () -> Bool in
            do {
                let models = try await CtcModels.downloadAndLoad()
                ctcBox = UncheckedSendableBox(models)
                return true
            } catch {
                logger.error("Vocabulary model load failed: \(error.localizedDescription)")
                return false
            }
        }
        ctcLoadTask = task
        let ok = await task.value
        ctcLoadTask = nil
        isVocabModelLoading = false
        vocabModelLoadFailed = !ok
        return ok
    }

    // MARK: - Start / Stop (live dictation → buffer, then ONE batch at stop)

    /// Reset state and mark capture active — cheap + synchronous so the mic can
    /// start and buffer instantly.
    func beginCapturing() {
        currentText = ""
        vadBuffer = []
        vadStreamState = .initial()
        lastSpeechTime = Date()
        detectedLanguage = ""
        lastConfidence = 0
        minTokenConfidence = 0
        avgTokenConfidence = 0
        isCapturing = true
    }

    /// Create the single, ordered audio pipeline and start its lone consumer.
    /// Returns the continuation the audio tap yields into. One ordered stream +
    /// one serial consumer = in-capture-order buffering, no races.
    func startAudioPipeline() -> AsyncStream<AVAudioPCMBuffer>.Continuation {
        audioConsumer?.cancel()
        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        audioConsumer = Task { @MainActor [weak self] in
            for await buffer in stream {
                await self?.feed(buffer)
            }
        }
        return continuation
    }

    /// Wait for the consumer to drain every remaining buffer after the
    /// continuation is finished, so the batch pass sees the complete audio.
    func awaitAudioConsumer() async {
        await audioConsumer?.value
        audioConsumer = nil
    }

    /// v2: no streaming session during recording — just confirm the batch engine
    /// is ready (so stop is fast). Audio is buffered by feed().
    func startTranscription() async {
        guard isModelLoaded, isCapturing else { return }
        if batchAsr == nil { _ = try? await batchEngine() }
        isTranscribing = true
    }

    /// Stop capture and transcribe the whole buffer in ONE batch pass (full
    /// context). Returns the final text.
    func stopTranscription(rawSamples: [Float], rate: Double) async -> String {
        isCapturing = false
        guard isTranscribing else { return currentText }
        isTranscribing = false
        await transcribeRecording(rawSamples, rate: rate)
        return currentText
    }

    // MARK: - Batch transcription (live buffer + files share one engine)

    private func batchEngine() async throws -> AsrManager {
        if let batchAsr { return batchAsr }
        guard let asrModels else {
            throw NSError(domain: "Stenote", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Speech model isn't loaded yet."])
        }
        let manager = AsrManager()
        try await manager.initialize(models: asrModels.value)
        batchAsr = manager
        return manager
    }

    /// Transcribe the buffered recording with the batch engine (full context),
    /// then apply the shared text pipeline. Sets `currentText`.
    private func transcribeRecording(_ rawSamples: [Float], rate: Double) async {
        // ONE clean conversion of the whole recording (input rate → 16 kHz), like
        // the file path — no per-buffer resampler warm-up to garble short clips.
        let samples = (rate <= 0 || rate == 16000) ? rawSamples : Self.resample(rawSamples, from: rate)
        guard samples.count >= 1600 else {   // < ~0.1 s of audio — nothing to do
            currentText = ""
            return
        }
        do {
            let asr = try await batchEngine()
            let result = try await asr.transcribe(samples, source: .microphone)
            let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { currentText = ""; return }

            var corrected = postProcess(trimmed)
            corrected = Self.removeTrailingStutter(corrected)

            let recognizer = NLLanguageRecognizer()
            recognizer.processString(corrected)
            if let lang = recognizer.dominantLanguage?.rawValue {
                detectedLanguage = String(lang.prefix(2))
            }
            currentText = corrected
            logger.info("batch transcript (\(corrected.count) chars): \(corrected.prefix(120))…")
        } catch {
            logger.error("Batch transcription failed: \(error.localizedDescription)")
            currentText = ""
        }
    }

    /// Single-shot resample of a complete mono signal (input rate → `outRate`),
    /// flushing held samples at end-of-stream. ONE filter warm-up for the whole
    /// recording (negligible) instead of one per buffer — this is what keeps short
    /// clips clean (per-buffer resampling garbled their warm-up-heavy start).
    static func resample(_ samples: [Float], from inRate: Double, to outRate: Double = 16000) -> [Float] {
        guard !samples.isEmpty, inRate > 0, inRate != outRate,
              let inFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inRate, channels: 1, interleaved: false),
              let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: outRate, channels: 1, interleaved: false),
              let conv = AVAudioConverter(from: inFmt, to: outFmt),
              let inBuf = AVAudioPCMBuffer(pcmFormat: inFmt, frameCapacity: AVAudioFrameCount(samples.count))
        else { return samples }
        inBuf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { inBuf.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }

        let outCap = AVAudioFrameCount((Double(samples.count) * outRate / inRate).rounded(.up)) + 4096
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: outCap) else { return samples }
        var error: NSError?
        var fed = false
        conv.convert(to: outBuf, error: &error) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return inBuf
        }
        guard error == nil, outBuf.frameLength > 0 else { return samples }
        return Array(UnsafeBufferPointer(start: outBuf.floatChannelData![0], count: Int(outBuf.frameLength)))
    }

    // MARK: - File transcription (batch)

    /// Transcribe an audio file (any length) with the batch ASR — full context,
    /// internal chunking. Applies word corrections, but NOT the dictation
    /// voice-commands (which don't fit arbitrary recordings).
    func transcribeFile(url: URL) async throws -> String {
        let asr = try await batchEngine()
        let result = try await asr.transcribe(url, source: .system)
        let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return textReplacement.applyReplacements(to: trimmed)
    }

    // MARK: - Audio Input (single ordered consumer)

    /// Buffer ONE audio buffer + feed VAD, in capture order. Called only by the
    /// lone consumer in `startAudioPipeline()`, so calls never overlap or reorder.
    private func feed(_ buffer: AVAudioPCMBuffer) async {
        guard isCapturing else { return }
        guard let channelData = buffer.floatChannelData else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        // This is the per-buffer-converted 16 kHz audio — used ONLY to drive VAD
        // auto-stop (which tolerates resampler artifacts). The ASR uses the raw
        // recording, converted in ONE shot at stop (AudioCaptureService.takeRecording).
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: count))
        await processVadSamples(samples)
    }

    // MARK: - VAD Processing

    private func processVadSamples(_ samples: [Float]) async {
        guard let vadManager else { return }

        vadBuffer.append(contentsOf: samples)

        let chunkSize = VadManager.chunkSize
        while vadBuffer.count >= chunkSize {
            let chunk = Array(vadBuffer[0..<chunkSize])
            vadBuffer.removeFirst(chunkSize)

            do {
                let vadConfig = VadSegmentationConfig(
                    minSpeechDuration: 0.25,         // Default 0.15 — filter click noises
                    minSilenceDuration: 0.75,        // Used only for auto-stop + paragraph-break timing
                    speechPadding: 0.15,             // Default 0.1 — prevent clipped word edges
                    silenceThresholdForSplit: 0.25,  // Default 0.3 — more sensitive to true silence
                    negativeThresholdOffset: 0.12    // Default 0.15 — faster speech-end detection
                )
                let result = try await vadManager.processStreamingChunk(
                    chunk,
                    state: vadStreamState,
                    config: vadConfig
                )
                vadStreamState = result.state

                if result.state.triggered {
                    lastSpeechTime = Date()
                }

                // Auto-stop after prolonged silence
                let timeout = SettingsStore.shared.autoStopTimeout
                if timeout != .off,
                   let lastSpeech = lastSpeechTime,
                   Date().timeIntervalSince(lastSpeech) >= TimeInterval(timeout.rawValue) {
                    onSilenceTimeout?()
                    return
                }
            } catch {
                // VAD error — continue
            }
        }
    }

    // MARK: - Text pipeline

    /// Replacements + (if enabled) voice commands + emoji — applied to the final
    /// batch transcript.
    private func postProcess(_ text: String) -> String {
        voiceCommands.process(textReplacement.applyReplacements(to: text))
    }

    /// Encoder-window geometry (kept for its unit tests + as documentation of the
    /// Parakeet 15 s / 240,000-sample input cap). Unused by the v2 batch path — the
    /// batch engine does its own internal context-preserving chunking — but retained
    /// so the invariant stays documented and tested for any future streaming work.
    struct StreamingWindow: Equatable {
        let chunkSeconds: Double
        let leftContextSeconds: Double
        let rightContextSeconds: Double
        let capSeconds: Double

        /// The full window assembled and fed to the encoder per step.
        var windowSeconds: Double { leftContextSeconds + chunkSeconds + rightContextSeconds }

        /// Clamp the desired knobs so `windowSeconds <= cap` always holds.
        static func clamped(desiredChunk: Double = 11.0,
                            desiredLeftContext: Double = 2.0,
                            rightContext: Double = 1.5,
                            cap: Double = 14.5) -> StreamingWindow {
            let chunk = min(desiredChunk, max(0, cap - rightContext))
            let maxLeft = max(0, cap - chunk - rightContext)
            let left = min(desiredLeftContext, maxLeft)
            return StreamingWindow(chunkSeconds: chunk,
                                   leftContextSeconds: left,
                                   rightContextSeconds: rightContext,
                                   capSeconds: cap)
        }
    }

    /// Detect and remove ASR stutter where the last 1-2 words are repeated.
    /// e.g. "hello world world" → "hello world". Pure + `static` so it's unit-tested.
    static func removeTrailingStutter(_ text: String) -> String {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)

        func normalize(_ word: String) -> String {
            word.lowercased().filter { !$0.isPunctuation }
        }

        // Check 2-word stutter first: "... w1 w2 w1 w2"
        if words.count >= 4 {
            let tailOriginal = Array(words.suffix(2))
            let tail = tailOriginal.map { normalize($0) }
            let before = words.dropLast(2).suffix(2).map { normalize($0) }
            // Keep capitalized repeats — likely a real proper noun ("New York, New York").
            let looksLikeProperNoun = tailOriginal.allSatisfy { $0.first?.isUppercase == true }
            if tail == before, tail.allSatisfy({ !$0.isEmpty }), !looksLikeProperNoun {
                logger.info("Stutter removed (2-word): '\(words.suffix(2).joined(separator: " "))'")
                return words.dropLast(2).joined(separator: " ")
            }
        }

        // Check 1-word stutter: "... w w" (min 3 chars to avoid false positives like "I I")
        if words.count >= 2 {
            let last = normalize(words[words.count - 1])
            let prev = normalize(words[words.count - 2])
            if last == prev && last.count >= 3 {
                logger.info("Stutter removed (1-word): '\(words.last!)'")
                return words.dropLast().joined(separator: " ")
            }
        }

        return text
    }
}
