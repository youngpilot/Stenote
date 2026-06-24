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
    private var vadManager: VadManager?
    private var ctcBox: UncheckedSendableBox<CtcModels>?

    private var ctcModels: CtcModels? { ctcBox?.value }

    // Lazy load state for the CTC vocabulary-boosting model (~98 MB).
    private(set) var isVocabModelLoading = false
    private(set) var vocabModelLoadFailed = false
    private var ctcLoadTask: Task<Bool, Never>?

    // --- Streaming state ---
    private var lastConfirmedText = ""      // used for volatile preview diff
    private var lastPastedConfirmedText = "" // delta tracking for incremental paste
    private var updateTask: Task<Void, Never>?
    private var isStopping = false          // guard against stale updates during finish()

    // --- VAD state (auto-stop + paragraph breaks) ---
    private var vadBuffer: [Float] = []
    private var vadStreamState: VadStreamState = .initial()
    private var lastSpeechTime: Date?
    private var lastSpeechEndTime: Date?
    private var pendingParagraphBreak = false

    // Language detection
    private(set) var detectedLanguage = ""
    // Confidence tracking
    private(set) var lastConfidence: Float = 0
    private(set) var minTokenConfidence: Float = 0
    private(set) var avgTokenConfidence: Float = 0

    var onSegmentReady: ((String) -> Void)?
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

    func startTranscription() async {
        guard isModelLoaded else { return }

        // Reset state
        currentText = ""
        vadBuffer = []
        vadStreamState = .initial()
        lastSpeechTime = Date()
        lastSpeechEndTime = nil
        pendingParagraphBreak = false
        detectedLanguage = ""

        await startStreaming()

        isTranscribing = true
    }

    func stopTranscription() async -> String {
        guard isTranscribing else { return currentText }
        await stopStreaming()
        isTranscribing = false
        return currentText
    }

    // MARK: - Audio Input

    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async {
        guard isTranscribing else { return }

        // Feed the streaming ASR engine
        if let asr = streamingAsr {
            nonisolated(unsafe) let sendableBuffer = buffer
            await asr.streamAudio(sendableBuffer)
        }

        // Extract samples for VAD (auto-stop + paragraph breaks)
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

                if let event = result.event {
                    switch event.kind {
                    case .speechStart:
                        if let lastEnd = lastSpeechEndTime,
                           Date().timeIntervalSince(lastEnd) > 2.5 {
                            pendingParagraphBreak = true
                        }
                    case .speechEnd:
                        lastSpeechEndTime = Date()
                    }
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
        guard let asrModels else { return }

        lastConfirmedText = ""
        lastPastedConfirmedText = ""
        isStopping = false
        minTokenConfidence = 0
        avgTokenConfidence = 0

        // Tuned config: faster confirmations, more context, lower latency
        let config = StreamingAsrConfig(
            chunkSeconds: 11.0,              // Good tradeoff for the TDT batch model
            hypothesisChunkSeconds: 0.5,     // Faster preview updates
            leftContextSeconds: 3.0,         // Better accuracy at chunk edges
            rightContextSeconds: 1.5,        // 0.5s less latency
            minContextForConfirmation: 5.0,  // Confirm text ~5s after speech
            confirmationThreshold: 0.85      // Stricter to compensate for less context
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
            logger.error("Failed to start streaming ASR: \(error)")
            return
        }

        streamingAsr = asr

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
                    corrected = removeTrailingStutter(corrected)

                    let recognizer = NLLanguageRecognizer()
                    recognizer.processString(corrected)
                    if let lang = recognizer.dominantLanguage?.rawValue {
                        detectedLanguage = String(lang.prefix(2))
                    }

                    currentText = corrected

                    // Only paste the delta not yet pasted during streaming
                    let delta = computeConfirmedDelta(old: lastPastedConfirmedText, new: corrected)
                    logger.info("finish (\(corrected.count) chars, delta: \(delta.count)): \(corrected.prefix(120))…")
                    if !delta.isEmpty {
                        let prefix = pendingParagraphBreak ? "\n\n" : ""
                        pendingParagraphBreak = false
                        onSegmentReady?(prefix + delta)
                    }
                } else {
                    logger.warning("finish() returned empty text!")
                }
            } catch {
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

    /// Detect and remove ASR stutter where the last 1-2 words are repeated.
    /// e.g. "hello world world" → "hello world"
    private func removeTrailingStutter(_ text: String) -> String {
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
            lastConfirmedText = corrected
            currentText = corrected
            logger.info("Confirmed (\(corrected.count) chars, avg:\(String(format: "%.0f", self.avgTokenConfidence * 100))%): \(corrected.prefix(60))…")

            // Incremental paste: only paste the delta since last paste
            if corrected.count > lastPastedConfirmedText.count {
                let delta = computeConfirmedDelta(old: lastPastedConfirmedText, new: corrected)
                if !delta.isEmpty {
                    let prefix = pendingParagraphBreak ? "\n\n" : ""
                    pendingParagraphBreak = false
                    onSegmentReady?(prefix + delta + " ")
                    lastPastedConfirmedText = corrected
                }
            }
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

    /// Word-level delta between old and new confirmed text.
    /// Robust against re-punctuation ("world" → "world,").
    private func computeConfirmedDelta(old: String, new: String) -> String {
        guard !old.isEmpty else { return new }
        let oldWords = old.split(separator: " ", omittingEmptySubsequences: true)
        let newWords = new.split(separator: " ", omittingEmptySubsequences: true)

        func normalize(_ word: Substring) -> String {
            word.lowercased().filter { !$0.isPunctuation }
        }

        var matchCount = 0
        for (o, n) in zip(oldWords, newWords) {
            if normalize(o) == normalize(n) {
                matchCount += 1
            } else {
                break
            }
        }

        let remaining = newWords[matchCount...]
        return remaining.joined(separator: " ")
    }
}
