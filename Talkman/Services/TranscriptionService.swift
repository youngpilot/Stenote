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

    // FluidAudio components
    // AsrManager is not Sendable but we guarantee single-writer access via @MainActor.
    // Using @unchecked Sendable wrapper to satisfy Swift 6 strict concurrency.
    private var asrBox: UncheckedSendableBox<AsrManager>?
    private var vadManager: VadManager?
    private var ctcBox: UncheckedSendableBox<CtcModels>?

    private var asrManager: AsrManager? { asrBox?.value }
    private var ctcModels: CtcModels? { ctcBox?.value }

    // Audio accumulation for VAD-triggered batch transcription
    private var accumulatedSamples: [Float] = []
    private var vadBuffer: [Float] = []  // Accumulates samples across callbacks for VAD chunks
    private var vadStreamState: VadStreamState = .initial()

    // Silence tracking for auto-stop
    private var silentChunkCount = 0
    private var lastSpeechTime: Date?

    // Paragraph break tracking
    private var lastSpeechEndTime: Date?
    private var pendingParagraphBreak = false

    // Periodic transcription — transcribe every N seconds even without VAD speechEnd
    // Only as a fallback; VAD speechEnd is the primary trigger
    private let periodicInterval: TimeInterval = 3.0
    private var lastTranscriptionTime: Date?
    private var isTranscribing_ASR = false  // Guard against overlapping ASR calls

    // Language detection
    private(set) var detectedLanguage = ""

    var onSegmentReady: ((String) -> Void)?
    var onSilenceTimeout: (() -> Void)?

    // MARK: - Model Loading

    func loadModel() async throws {
        // 1. Download and load ASR models (v3 = multilingual 25 EU languages)
        modelLoadingStep = "Downloading ASR model… (1/4)"
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        modelLoadingStep = "Initializing ASR engine… (2/4)"
        let manager = AsrManager(config: .default)
        try await manager.initialize(models: models)
        asrBox = UncheckedSendableBox(manager)

        // 2. Initialize VAD (downloads Silero model on first launch)
        modelLoadingStep = "Loading VAD model… (3/4)"
        vadManager = try await VadManager()

        // 3. Download CTC models for vocabulary boosting
        modelLoadingStep = "Loading CTC model… (4/4)"
        ctcBox = UncheckedSendableBox(try await CtcModels.downloadAndLoad())

        // 4. Configure vocabulary boosting if brand names exist
        modelLoadingStep = "Configuring vocabulary…"
        await configureVocabularyBoosting()

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

        let brandNames = textReplacement.replacements
        let boostWords = textReplacement.boostWords
        guard !brandNames.isEmpty || !boostWords.isEmpty else {
            asrBox.value.disableVocabularyBoosting()
            return
        }

        // Convert brand names to CustomVocabularyTerms
        var terms = brandNames.map { from, to in
            CustomVocabularyTerm(
                text: to,
                weight: 10.0,
                aliases: [from]
            )
        }

        // Add boost-only words (no alias, just boost the correct spelling)
        terms += boostWords.map { word in
            CustomVocabularyTerm(text: word, weight: 10.0)
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

    // MARK: - Transcription Flow

    func startTranscription() {
        guard isModelLoaded else { return }
        isTranscribing = true
        currentText = ""
        segments = []
        accumulatedSamples = []
        vadBuffer = []
        vadStreamState = .initial()
        silentChunkCount = 0
        lastSpeechTime = Date()
        lastSpeechEndTime = nil
        pendingParagraphBreak = false
        lastTranscriptionTime = Date()
        isTranscribing_ASR = false
        detectedLanguage = ""
    }

    func processAudioSamples(_ samples: [Float]) async {
        guard isTranscribing, let vadManager else { return }
        guard !samples.isEmpty else { return }

        // Accumulate all audio for transcription
        accumulatedSamples.append(contentsOf: samples)

        // Accumulate samples across callbacks for VAD (chunkSize=4096, callbacks ~1365)
        vadBuffer.append(contentsOf: samples)

        // Drain vadBuffer in chunkSize pieces
        let chunkSize = VadManager.chunkSize
        while vadBuffer.count >= chunkSize {
            let chunk = Array(vadBuffer[0..<chunkSize])
            vadBuffer.removeFirst(chunkSize)

            do {
                let vadConfig = VadSegmentationConfig(
                    minSilenceDuration: SettingsStore.shared.vadSensitivity.minSilenceDuration
                )
                let result = try await vadManager.processStreamingChunk(
                    chunk,
                    state: vadStreamState,
                    config: vadConfig
                )
                vadStreamState = result.state

                // Keep lastSpeechTime fresh while speech is active
                // (prevents auto-stop during continuous speaking without VAD events)
                if result.state.triggered {
                    lastSpeechTime = Date()
                }

                if let event = result.event {
                    switch event.kind {
                    case .speechStart:
                        // Check for paragraph break (gap > 2.5s since last speech end)
                        if let lastEnd = lastSpeechEndTime,
                           Date().timeIntervalSince(lastEnd) > 2.5 {
                            pendingParagraphBreak = true
                        }
                    case .speechEnd:
                        lastSpeechEndTime = Date()
                        await transcribeAccumulated()
                    }
                }

                // Auto-stop after prolonged silence (0 = disabled)
                let timeout = SettingsStore.shared.autoStopTimeout
                if timeout != .off,
                   let lastSpeech = lastSpeechTime,
                   Date().timeIntervalSince(lastSpeech) >= TimeInterval(timeout.rawValue) {
                    onSilenceTimeout?()
                    return
                }
            } catch {
                // VAD error — continue accumulating
            }
        }

        // Periodic transcription: if enough audio has accumulated without a VAD speechEnd,
        // transcribe now so text appears while the user is still speaking
        if !isTranscribing_ASR,
           accumulatedSamples.count >= 16_000,  // at least 1s of audio
           let lastTime = lastTranscriptionTime,
           Date().timeIntervalSince(lastTime) >= periodicInterval {
            await transcribeAccumulated(isMidSpeech: true)
        }
    }

    private func transcribeAccumulated(isMidSpeech: Bool = false) async {
        guard !accumulatedSamples.isEmpty, let asrBox, !isTranscribing_ASR else { return }

        // Need at least 0.5 seconds of audio (8000 samples at 16kHz)
        // Check BEFORE moving samples out — otherwise short chunks are lost forever
        guard accumulatedSamples.count >= 8_000 else { return }

        isTranscribing_ASR = true
        defer { isTranscribing_ASR = false }

        let samplesToTranscribe = accumulatedSamples
        accumulatedSamples = []
        lastTranscriptionTime = Date()

        do {
            let result = try await asrBox.value.transcribe(samplesToTranscribe, source: .microphone)
            let rawText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawText.isEmpty else { return }

            // Apply regex replacements as fallback (vocab boosting handles most cases)
            var corrected = textReplacement.applyReplacements(to: rawText)

            // Strip trailing sentence punctuation from mid-speech chunks —
            // the ASR model thinks each chunk is a complete sentence
            if isMidSpeech {
                while corrected.last == "." || corrected.last == "?" || corrected.last == "!" {
                    corrected.removeLast()
                }
                corrected = corrected.trimmingCharacters(in: .whitespaces)
                guard !corrected.isEmpty else { return }
            }

            // Detect language using NaturalLanguage
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

            // Insert paragraph break prefix if a long pause was detected
            let prefix = pendingParagraphBreak ? "\n\n" : ""
            pendingParagraphBreak = false
            onSegmentReady?(prefix + corrected)
        } catch {
            logger.error("Transcription error: \(error)")
        }
    }

    func stopTranscription() async -> String {
        guard isTranscribing else { return currentText }

        // Flush any remaining vadBuffer samples into accumulated
        if !vadBuffer.isEmpty {
            accumulatedSamples.append(contentsOf: vadBuffer)
            vadBuffer = []
        }

        // Reset ASR guard so final transcription can run
        isTranscribing_ASR = false

        // Transcribe ALL remaining audio — never discard
        if !accumulatedSamples.isEmpty {
            // Pad short audio to minimum 0.5s so ASR can process it
            let minSamples = 8_000
            if accumulatedSamples.count < minSamples {
                accumulatedSamples.append(contentsOf: [Float](repeating: 0, count: minSamples - accumulatedSamples.count))
            }
            await transcribeAccumulated()
        }

        isTranscribing = false
        return currentText
    }
}
