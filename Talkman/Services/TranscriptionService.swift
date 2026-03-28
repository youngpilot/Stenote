import AVFoundation
import FluidAudio
import Foundation
import NaturalLanguage
import Observation
import os

private let logger = Logger(subsystem: "com.youngpilot.Talkman", category: "Transcription")

@Observable
@MainActor
final class TranscriptionService {
    private(set) var isModelLoaded = false
    private(set) var isTranscribing = false
    private(set) var currentText = ""
    private(set) var segments: [TranscriptionSegment] = []
    private(set) var modelLoadingStep = ""

    private let textReplacement = TextReplacementService.shared
    private let voiceCommands = VoiceCommandService.shared

    // Shared FluidAudio components
    private var asrModels: UncheckedSendableBox<AsrModels>?
    private var asrBox: UncheckedSendableBox<AsrManager>?  // For Live mode
    private var streamingAsr: StreamingAsrManager?          // For Accurate mode
    private var vadManager: VadManager?
    private var ctcBox: UncheckedSendableBox<CtcModels>?

    private var asrManager: AsrManager? { asrBox?.value }
    private var ctcModels: CtcModels? { ctcBox?.value }

    // Which mode is active for current session
    private var activeMode: TranscriptionMode = .live

    // --- Live mode state ---
    private var accumulatedSamples: [Float] = []
    private let periodicInterval: TimeInterval = 3.0
    private var lastTranscriptionTime: Date?
    private var isTranscribing_ASR = false

    // --- Accurate mode state ---
    private var lastConfirmedText = ""  // used for volatile preview diff
    private var updateTask: Task<Void, Never>?
    private var isStopping = false      // guard against stale updates during finish()

    // --- Shared VAD state ---
    private var vadBuffer: [Float] = []
    private var vadStreamState: VadStreamState = .initial()
    private var lastSpeechTime: Date?
    private var lastSpeechEndTime: Date?
    private var pendingParagraphBreak = false

    // Language detection
    private(set) var detectedLanguage = ""
    // Confidence tracking
    private(set) var lastConfidence: Float = 0
    private(set) var lastRtfx: Float = 0

    var onSegmentReady: ((String) -> Void)?
    var onSilenceTimeout: (() -> Void)?

    // MARK: - Model Loading

    func loadModel() async throws {
        modelLoadingStep = "Downloading ASR model… (1/3)"
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        asrModels = UncheckedSendableBox(models)

        // Initialize batch ASR manager with tuned TDT config (used in Live mode)
        modelLoadingStep = "Initializing ASR engine… (2/3)"
        let tdtConfig = TdtConfig(
            boundarySearchFrames: 30,    // Default 20 — more search at chunk edges
            maxTokensPerChunk: 200,      // Default 150 — allow longer chunks
            consecutiveBlankLimit: 8     // Default 5 — less aggressive termination
        )
        let asrConfig = ASRConfig(tdtConfig: tdtConfig)
        let manager = AsrManager(config: asrConfig)
        try await manager.initialize(models: models)
        asrBox = UncheckedSendableBox(manager)

        // Initialize VAD
        modelLoadingStep = "Loading VAD model… (3/3)"
        vadManager = try await VadManager()

        // Download CTC models for vocabulary boosting
        ctcBox = UncheckedSendableBox(try await CtcModels.downloadAndLoad())

        modelLoadingStep = ""
        isModelLoaded = true
    }

    // MARK: - Vocabulary Boosting

    func configureVocabularyBoosting() async {
        guard let asrBox, let ctcBox else { return }

        guard SettingsStore.shared.enableVocabBoosting else {
            asrBox.value.disableVocabularyBoosting()
            return
        }

        let terms = buildVocabularyTerms()
        guard !terms.isEmpty else {
            asrBox.value.disableVocabularyBoosting()
            return
        }

        let vocabContext = CustomVocabularyContext(terms: terms)
        do {
            try await asrBox.value.configureVocabularyBoosting(
                vocabulary: vocabContext,
                ctcModels: ctcBox.value
            )
        } catch {
            logger.warning("Vocabulary boosting setup failed: \(error)")
        }
    }

    private func buildVocabularyTerms() -> [CustomVocabularyTerm] {
        let brandNames = textReplacement.replacements
        let boostWords = textReplacement.boostWords
        guard !brandNames.isEmpty || !boostWords.isEmpty else { return [] }

        var terms = brandNames.map { from, to in
            CustomVocabularyTerm(text: to, weight: 10.0, aliases: [from])
        }
        terms += boostWords.map { word in
            CustomVocabularyTerm(text: word, weight: 10.0)
        }
        return terms
    }

    // MARK: - Start / Stop

    func startTranscription() async {
        guard isModelLoaded else { return }

        activeMode = SettingsStore.shared.transcriptionMode

        // Reset shared state
        currentText = ""
        segments = []
        vadBuffer = []
        vadStreamState = .initial()
        lastSpeechTime = Date()
        lastSpeechEndTime = nil
        pendingParagraphBreak = false
        detectedLanguage = ""

        if activeMode == .accurate {
            await startAccurateMode()
        } else {
            startLiveMode()
        }

        isTranscribing = true
    }

    func stopTranscription() async -> String {
        guard isTranscribing else { return currentText }

        if activeMode == .accurate {
            await stopAccurateMode()
        } else {
            await stopLiveMode()
        }

        isTranscribing = false
        return currentText
    }

    // MARK: - Audio Input

    func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async {
        guard isTranscribing else { return }

        if activeMode == .accurate {
            // Feed to streaming ASR
            if let asr = streamingAsr {
                nonisolated(unsafe) let sendableBuffer = buffer
                await asr.streamAudio(sendableBuffer)
            }
        }

        // Extract samples for VAD + Live mode
        guard let channelData = buffer.floatChannelData else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: count))

        if activeMode == .live {
            accumulatedSamples.append(contentsOf: samples)
        }

        await processVadSamples(samples)

        // Live mode: periodic transcription fallback
        if activeMode == .live {
            if !isTranscribing_ASR,
               accumulatedSamples.count >= 16_000,
               let lastTime = lastTranscriptionTime,
               Date().timeIntervalSince(lastTime) >= periodicInterval {
                await transcribeAccumulatedLive(isMidSpeech: true)
            }
        }
    }

    // MARK: - VAD Processing (shared)

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
                    minSilenceDuration: SettingsStore.shared.vadSensitivity.minSilenceDuration,
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
                        // Live mode: transcribe on speech end
                        if activeMode == .live {
                            await transcribeAccumulatedLive()
                        }
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

    // MARK: - Live Mode

    private func startLiveMode() {
        accumulatedSamples = []
        lastTranscriptionTime = Date()
        isTranscribing_ASR = false

        // Reconfigure vocab boosting on the batch ASR manager
        Task { await configureVocabularyBoosting() }
    }

    private func stopLiveMode() async {
        // Wait for any in-flight transcription to complete before transcribing
        // remaining audio. Without this, resetting isTranscribing_ASR while a
        // transcription is awaiting allows two concurrent calls → duplicate text.
        for _ in 0..<100 { // max ~1s
            if !isTranscribing_ASR { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        // Flush remaining VAD buffer into accumulated
        if !vadBuffer.isEmpty {
            accumulatedSamples.append(contentsOf: vadBuffer)
            vadBuffer = []
        }

        // Transcribe ALL remaining audio — never discard
        if !accumulatedSamples.isEmpty {
            let minSamples = 8_000
            if accumulatedSamples.count < minSamples {
                accumulatedSamples.append(contentsOf: [Float](repeating: 0, count: minSamples - accumulatedSamples.count))
            }
            await transcribeAccumulatedLive()
        }
    }

    private func transcribeAccumulatedLive(isMidSpeech: Bool = false) async {
        guard !accumulatedSamples.isEmpty, let asrBox, !isTranscribing_ASR else { return }
        guard accumulatedSamples.count >= 8_000 else { return }

        isTranscribing_ASR = true
        defer { isTranscribing_ASR = false }

        let samplesToTranscribe = accumulatedSamples
        accumulatedSamples = []
        lastTranscriptionTime = Date()

        do {
            let result = try await asrBox.value.transcribe(samplesToTranscribe, source: .microphone)
            lastConfidence = result.confidence
            lastRtfx = result.rtfx
            let rawText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawText.isEmpty else { return }

            var corrected = textReplacement.applyReplacements(to: rawText)

            // Strip trailing punctuation from mid-speech chunks
            if isMidSpeech {
                while corrected.last == "." || corrected.last == "?" || corrected.last == "!" {
                    corrected.removeLast()
                }
                corrected = corrected.trimmingCharacters(in: .whitespaces)
                guard !corrected.isEmpty else { return }
            }

            corrected = removeTrailingStutter(corrected)
            corrected = voiceCommands.process(corrected)

            // Detect language
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(corrected)
            if let lang = recognizer.dominantLanguage?.rawValue {
                detectedLanguage = String(lang.prefix(2))
            }

            let segment = TranscriptionSegment(
                text: corrected,
                timestamp: Date(),
                language: detectedLanguage.isEmpty ? nil : detectedLanguage,
                isFinal: true
            )
            segments.append(segment)
            currentText = segments.map(\.text).joined(separator: " ")

            let prefix = pendingParagraphBreak ? "\n\n" : ""
            pendingParagraphBreak = false
            onSegmentReady?(prefix + corrected)
        } catch {
            logger.error("Transcription error: \(error)")
        }
    }

    // MARK: - Accurate Mode

    private func startAccurateMode() async {
        guard let asrModels else { return }

        lastConfirmedText = ""
        isStopping = false

        let asr = StreamingAsrManager(config: .streaming)

        // Configure vocabulary boosting on streaming manager
        if SettingsStore.shared.enableVocabBoosting, let ctcModels {
            let terms = buildVocabularyTerms()
            if !terms.isEmpty {
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

    private func stopAccurateMode() async {
        // Block stale updates from overwriting currentText during finish()
        isStopping = true
        updateTask?.cancel()
        updateTask = nil

        logger.info("stopAccurateMode: lastConfirmedText=\(self.lastConfirmedText.count) chars")

        if let asr = streamingAsr {
            do {
                let finalText = try await asr.finish()
                logger.info("finish() raw=\(finalText.count) chars: \(finalText.prefix(120))…")

                let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    var corrected = textReplacement.applyReplacements(to: trimmed)
                    corrected = removeTrailingStutter(corrected)
                    corrected = voiceCommands.process(corrected)

                    let recognizer = NLLanguageRecognizer()
                    recognizer.processString(corrected)
                    if let lang = recognizer.dominantLanguage?.rawValue {
                        detectedLanguage = String(lang.prefix(2))
                    }

                    currentText = corrected
                    logger.info("Accurate finish (\(corrected.count) chars): \(corrected.prefix(120))…")
                    onSegmentReady?(corrected)
                } else {
                    logger.warning("finish() returned empty text!")
                }
            } catch {
                logger.error("Streaming ASR finish error: \(error)")
            }
        }

        streamingAsr = nil
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
            let tail = words.suffix(2).map { normalize($0) }
            let before = words.dropLast(2).suffix(2).map { normalize($0) }
            if tail == before && tail.allSatisfy({ !$0.isEmpty }) {
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

        let corrected = textReplacement.applyReplacements(to: rawText)

        if update.isConfirmed {
            lastConfirmedText = corrected
            currentText = corrected
            logger.info("Confirmed (\(corrected.count) chars): \(corrected.prefix(60))…")
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
