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
    private var streamingAsr: StreamingAsrManager?
    private var batchAsr: AsrManager?        // batch engine for file transcription (lazy)
    private var vadManager: VadManager?
    private var ctcBox: UncheckedSendableBox<CtcModels>?

    private var ctcModels: CtcModels? { ctcBox?.value }

    // Lazy load state for the CTC vocabulary-boosting model (~98 MB).
    private(set) var isVocabModelLoading = false
    private(set) var vocabModelLoadFailed = false
    private var ctcLoadTask: Task<Bool, Never>?

    // --- Streaming state ---
    private var lastConfirmedText = ""      // used for volatile preview diff
    private var updateTask: Task<Void, Never>?
    private var isStopping = false          // guard against stale updates during finish()
    private var isCapturing = false         // mic is live; hold audio until ASR is ready
    private var pendingAudio: [AVAudioPCMBuffer] = []  // audio captured before asr.start()
    private var audioConsumer: Task<Void, Never>?     // lone, serial consumer of the audio stream
    /// Hard cap on held pre-roll buffers (~50s) so a slow/failed ASR start can
    /// never grow RAM without bound. Real pre-roll until the ASR is ready is ~1s.
    private static let maxPrerollBuffers = 600

    // --- VAD state (auto-stop) ---
    private var vadBuffer: [Float] = []
    private var vadStreamState: VadStreamState = .initial()
    private var lastSpeechTime: Date?

    // Language detection
    private(set) var detectedLanguage = ""
    // Confidence tracking
    private(set) var lastConfidence: Float = 0
    private(set) var minTokenConfidence: Float = 0
    private(set) var avgTokenConfidence: Float = 0

    var onSilenceTimeout: (() -> Void)?

    // MARK: - Model Loading

    func loadModel() async throws {
        modelLoadingStep = "Downloading ASR model… (1/2)"
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        asrModels = UncheckedSendableBox(models)

        // VAD powers auto-stop and paragraph-break detection
        modelLoadingStep = "Loading VAD model… (2/2)"
        vadManager = try await VadManager()

        // The CTC vocabulary model (~98 MB) is downloaded lazily the first time
        // the user enables Model Boosting — see ensureVocabModelsLoaded().

        modelLoadingStep = ""
        isModelLoaded = true
    }

    // MARK: - Vocabulary Boosting

    /// Idempotently download + load the CTC model used for vocabulary boosting.
    /// Triggered when the user enables Model Boosting, and awaited (as a no-op
    /// once loaded) before each session. Returns true when the model is ready.
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

    private func buildVocabularyTerms() -> [CustomVocabularyTerm] {
        let brandNames = textReplacement.replacements
        let boostWords = textReplacement.boostWords
        guard !brandNames.isEmpty || !boostWords.isEmpty else { return [] }

        // Note: FluidAudio ignores the per-term `weight` field — boosting strength
        // is a global, length-adaptive constant inside the rescorer — so we omit it.
        var terms = brandNames.map { from, to in
            CustomVocabularyTerm(text: to, aliases: [from])
        }
        terms += boostWords.map { word in
            CustomVocabularyTerm(text: word)
        }
        return terms
    }

    // MARK: - Start / Stop

    /// Reset state and mark capture active — cheap and synchronous, so the mic
    /// can start (and audio buffer) instantly. Then call startTranscription() to
    /// spin up the ASR in the background.
    func beginCapturing() {
        currentText = ""
        vadBuffer = []
        vadStreamState = .initial()
        lastSpeechTime = Date()
        detectedLanguage = ""
        pendingAudio = []
        isCapturing = true
    }

    /// Create the single, ordered audio pipeline and start its lone consumer.
    /// Returns the continuation the audio tap yields into.
    ///
    /// CRITICAL: audio must reach the streaming ASR strictly in capture order and
    /// without overlap. Feeding it from one `Task` per buffer (which bounce
    /// through the global pool and interleave via actor reentrancy) scrambles the
    /// timeline and makes the model drop whole chunks mid-recording. One ordered
    /// `AsyncStream` drained by one serial consumer guarantees in-order delivery.
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
    /// continuation is finished, so finish() sees the complete audio.
    func awaitAudioConsumer() async {
        await audioConsumer?.value
        audioConsumer = nil
    }

    func startTranscription() async {
        guard isModelLoaded, isCapturing else { return }
        await startStreaming()
        isTranscribing = true
    }

    func stopTranscription() async -> String {
        isCapturing = false
        guard isTranscribing else { return currentText }
        await stopStreaming()
        isTranscribing = false
        return currentText
    }

    // MARK: - File transcription (batch)

    /// Transcribe an audio file (any length) with the BATCH ASR — full context,
    /// internal chunking, no streaming windows (so the encoder-window limit can't
    /// apply). Reuses the loaded models via a lazily-created AsrManager. Applies
    /// word corrections, but NOT the dictation voice-commands (which don't fit
    /// arbitrary recordings). Throws if models aren't loaded or the clip is < ~1s.
    func transcribeFile(url: URL) async throws -> String {
        guard let asrModels else {
            throw NSError(domain: "Stenote", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Speech model isn't loaded yet."])
        }
        let asr: AsrManager
        if let existing = batchAsr {
            asr = existing
        } else {
            let manager = AsrManager()
            try await manager.initialize(models: asrModels.value)
            batchAsr = manager
            asr = manager
        }
        let result = try await asr.transcribe(url, source: .system)
        let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return textReplacement.applyReplacements(to: trimmed)
    }

    // MARK: - Audio Input (single ordered consumer)

    /// Feed ONE buffer to the ASR, in order. Called only by the lone consumer in
    /// `startAudioPipeline()`, so calls never overlap and never reorder.
    private func feed(_ buffer: AVAudioPCMBuffer) async {
        guard isCapturing else { return }

        // Feed the streaming ASR — or hold audio (in order) until it's ready,
        // then flush the pre-roll before the first live buffer so no words are
        // lost and nothing is fed out of order.
        if let asr = streamingAsr {
            if !pendingAudio.isEmpty {
                let preroll = pendingAudio
                pendingAudio = []
                for buf in preroll {
                    nonisolated(unsafe) let b = buf
                    await asr.streamAudio(b)
                }
            }
            nonisolated(unsafe) let sendableBuffer = buffer
            await asr.streamAudio(sendableBuffer)
        } else {
            // Hold pre-roll (normally ~1s, until the ASR finishes starting).
            // Safety cap so a slow or failed ASR start can never grow this
            // without bound on a long recording — RAM stays bounded regardless.
            pendingAudio.append(buffer)
            if pendingAudio.count > Self.maxPrerollBuffers {
                pendingAudio.removeFirst(pendingAudio.count - Self.maxPrerollBuffers)
            }
        }

        // Extract samples for VAD (auto-stop)
        guard let channelData = buffer.floatChannelData else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
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

    // MARK: - Streaming Transcription

    private func startStreaming() async {
        guard let asrModels else {
            // No models — abort cleanly so feed() stops buffering (bounded RAM).
            pendingAudio = []
            isCapturing = false
            return
        }

        lastConfirmedText = ""
        isStopping = false
        minTokenConfidence = 0
        avgTokenConfidence = 0

        // --- Streaming window MUST fit the encoder's fixed input ---
        // The Parakeet encoder input is hard-fixed at 15s / 240,000 samples
        // (FluidAudio ASRConstants.maxModelSamples). Each streaming window is
        // leftContext + chunk + rightContext. If that exceeds the cap, the encoder
        // throws a shape error that FluidAudio SILENTLY swallows (processWindow's
        // catch drops the whole chunk: no tokens, no update). That is exactly what
        // made the middle of long recordings vanish — window 1 has no left context
        // yet and the final flush has no right context, so only the middle windows
        // (left+chunk+right = full size) overflowed.
        //
        // We CLAMP leftContext so the assembled window can never exceed the cap, no
        // matter how the other knobs are tuned later. This makes the failure mode
        // structurally impossible rather than relying on hand-picked numbers.
        // The clamp lives in `StreamingWindow.clamped` (pure + static) so the
        // invariant (window <= cap) is unit-tested, not a debug-only assert.
        let window = StreamingWindow.clamped()

        let config = StreamingAsrConfig(
            chunkSeconds: window.chunkSeconds,             // good tradeoff for the TDT model
            hypothesisChunkSeconds: 0.5,                   // faster preview updates
            leftContextSeconds: window.leftContextSeconds, // clamped so window <= encoder cap
            rightContextSeconds: window.rightContextSeconds,
            minContextForConfirmation: 5.0,                // confirm text ~5s after speech
            confirmationThreshold: 0.85                    // stricter to compensate for less left context
        )
        let asr = StreamingAsrManager(config: config)

        // Optional vocabulary boosting (off by default). The CTC model loads
        // lazily; if it isn't ready yet (e.g. first use while offline), skip
        // boosting for this session rather than blocking or failing recording.
        if SettingsStore.shared.enableVocabBoosting {
            let terms = buildVocabularyTerms()
            if !terms.isEmpty, await ensureVocabModelsLoaded(), let ctcModels {
                let vocabContext = CustomVocabularyContext(terms: terms)
                do {
                    try await asr.configureVocabularyBoosting(
                        vocabulary: vocabContext,
                        ctcModels: ctcModels
                    )
                } catch {
                    logger.warning("Vocabulary boosting setup failed: \(error)")
                }
            }
        }

        do {
            try await asr.start(models: asrModels.value, source: .microphone)
        } catch {
            // ASR failed to start: stop buffering so pendingAudio can't grow
            // without bound (bounded RAM); the session ends with no text.
            logger.error("Failed to start streaming ASR: \(error)")
            pendingAudio = []
            isCapturing = false
            return
        }

        streamingAsr = asr
        // Pre-roll is flushed by the single audio consumer (`feed`), in capture
        // order — never from two places at once.

        updateTask = Task { [weak self] in
            for await update in await asr.transcriptionUpdates {
                await MainActor.run {
                    self?.handleStreamingUpdate(update)
                }
            }
        }
    }

    private func stopStreaming() async {
        // Block stale updates from overwriting currentText during finish()
        isStopping = true
        updateTask?.cancel()
        updateTask = nil

        logger.info("stopStreaming: lastConfirmedText=\(self.lastConfirmedText.count) chars")

        if let asr = streamingAsr {
            do {
                let finalText = try await asr.finish()
                logger.info("finish() raw=\(finalText.count) chars: \(finalText.prefix(120))…")

                let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    var corrected = postProcess(trimmed)
                    corrected = Self.removeTrailingStutter(corrected)

                    let recognizer = NLLanguageRecognizer()
                    recognizer.processString(corrected)
                    if let lang = recognizer.dominantLanguage?.rawValue {
                        detectedLanguage = String(lang.prefix(2))
                    }

                    // Final, complete transcript. RecordingManager pastes it once.
                    // Note: this text and FluidAudio's accumulated tokens are
                    // inherently O(recording length) — the price of a complete
                    // transcript. The AUDIO path is bounded; this grows only
                    // ~150 KB/hour, which is negligible.
                    currentText = corrected
                    logger.info("finish (\(corrected.count) chars): \(corrected.prefix(120))…")
                } else {
                    // finish() is authoritative: if it produced no final text,
                    // clear rather than paste a stale streaming-preview fragment.
                    currentText = ""
                    logger.warning("finish() returned empty text!")
                }
            } catch {
                // On a finish() error, keep the last streaming preview as a
                // best-effort fallback rather than losing everything.
                logger.error("Streaming ASR finish error: \(error)")
            }
        }

        streamingAsr = nil
    }

    /// Replacements + (if enabled) voice commands + emoji — the shared text
    /// pipeline applied to BOTH the streaming confirmed text and the final
    /// result, so the final paste delta lines up with what streaming pasted.
    private func postProcess(_ text: String) -> String {
        voiceCommands.process(textReplacement.applyReplacements(to: text))
    }

    /// Streaming-window geometry, clamped so the assembled window
    /// (left + chunk + right) can NEVER exceed the encoder's fixed input cap
    /// (15s / 240,000 samples). Exceeding it makes FluidAudio silently drop the
    /// chunk — the root cause of the v0.8.6 "middle of long recordings vanished"
    /// bug. Pure + static so the `window <= cap` invariant is unit-tested.
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
    /// e.g. "hello world world" → "hello world"
    /// Pure (input → output); `static` so the pipeline behavior is unit-testable.
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

    private func handleStreamingUpdate(_ update: StreamingTranscriptionUpdate) {
        guard !isStopping else { return }
        let rawText = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else { return }

        lastConfidence = update.confidence

        // Per-token confidence from TokenTiming
        let timings = update.tokenTimings
        if !timings.isEmpty {
            let confidences = timings.map(\.confidence)
            minTokenConfidence = confidences.min() ?? 0
            avgTokenConfidence = confidences.reduce(0, +) / Float(confidences.count)
        }

        let corrected = postProcess(rawText)

        if update.isConfirmed {
            // Update the live preview only — the full text is pasted once at stop.
            lastConfirmedText = corrected
            currentText = corrected
        } else {
            // Volatile — show as preview
            if corrected.hasPrefix(lastConfirmedText) {
                let preview = String(corrected.dropFirst(lastConfirmedText.count))
                    .trimmingCharacters(in: .whitespaces)
                if !preview.isEmpty {
                    currentText = lastConfirmedText.isEmpty ? preview : lastConfirmedText + " " + preview
                }
            }
        }
    }
}
