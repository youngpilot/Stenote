import Foundation
import os
#if canImport(FoundationModels)
import FoundationModels
#endif

private let logger = Logger(subsystem: "com.youngpilot.Steneo", category: "TextCleanup")

/// How dictated text is cleaned up after transcription. The user picks this in
/// Settings → Text Output.
enum CleanupMode: String, CaseIterable, Identifiable {
    case off       // leave the transcript exactly as spoken
    case rules     // deterministic filler-word removal — instant, never changes wording
    case ai        // on-device LLM (Apple Foundation Models) — smarter, can rephrase
    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Off"
        case .rules: return "Rules"
        case .ai: return "AI"
        }
    }
}

#if canImport(FoundationModels)
/// Guided-generation schema: forcing the model to fill a typed field (instead of
/// free-form prose) is what stops it prepending "Here is the cleaned text:".
@available(macOS 26.0, *)
@Generable
struct CleanedDictation {
    @Guide(description: "The cleaned text only — same language as the input, nothing added, no preamble or commentary.")
    var text: String
}
#endif

/// On-device cleanup of dictated text:
/// - `.rules`: deterministic, instant, NEVER changes the actual wording (safe in any
///   language). Filler removal only — punctuation/caps already come from the speech model.
/// - `.ai`: Apple's on-device Foundation Models (macOS 26+, Apple Intelligence enabled)
///   — smarter (also fixes light grammar) but can rephrase; falls back to `.rules`
///   when the model is unavailable or misfires.
/// Everything runs on-device — text never leaves the Mac.
@MainActor
final class TextCleanupService {
    static let shared = TextCleanupService()
    private init() {}

    /// A pre-warmed session (kept as AnyObject because `LanguageModelSession` is
    /// macOS 26+ only and this type deploys to 15.2). Created by `prewarm()` when an
    /// AI-mode recording starts, consumed by the next cleanup.
    private var sessionBox: AnyObject?

    /// True when the Apple Foundation Models on-device LLM can be used (so `.ai`
    /// actually runs the model rather than falling back to rules).
    var usesAppleIntelligence: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    /// Clean `text` according to `mode`. Never throws. `await` is free for the
    /// `.off` / `.rules` paths — they return synchronously.
    func cleanup(_ text: String, mode: CleanupMode) async -> String {
        switch mode {
        case .off:   return text
        case .rules: return Self.deterministicCleanup(text)
        case .ai:    return await cleanupWithAI(text)
        }
    }

    /// Warm up the on-device model so AI cleanup is fast when recording stops. Call
    /// when recording starts (only in `.ai` mode). No-op when unavailable.
    func prewarm() {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), SystemLanguageModel.default.isAvailable {
            let session = LanguageModelSession(instructions: Self.instructions)
            session.prewarm()
            sessionBox = session
        }
        #endif
    }

    /// AI path: on-device LLM, with the deterministic rules as a safety net on any
    /// failure (unavailable model, throw, or an obviously bad output).
    private func cleanupWithAI(_ text: String) async -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), SystemLanguageModel.default.isAvailable {
            if let cleaned = await cleanupWithModel(trimmed) { return cleaned }
        }
        #endif
        return Self.deterministicCleanup(trimmed)
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func cleanupWithModel(_ text: String) async -> String? {
        // Use the pre-warmed session if we have one (fast); else make a fresh one.
        let session = (sessionBox as? LanguageModelSession) ?? LanguageModelSession(instructions: Self.instructions)
        sessionBox = nil
        let options = GenerationOptions(
            sampling: .greedy,
            maximumResponseTokens: min(2000, max(128, text.count)))
        do {
            // Guided generation: the model fills `CleanedDictation.text` — no room
            // for a "Here is the cleaned text:" preamble.
            let response = try await session.respond(
                to: text, generating: CleanedDictation.self, options: options)
            let cleaned = Self.stripPreamble(response.content.text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Reject obvious misfires (empty, or wildly longer than the input — a
            // sign it added commentary) and fall back to deterministic instead.
            guard !cleaned.isEmpty, cleaned.count <= max(40, text.count * 3) else {
                logger.warning("Cleanup model output rejected; using fallback")
                return nil
            }
            return cleaned
        } catch {
            logger.warning("Cleanup model failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static let instructions = """
    You clean up raw dictated speech-to-text. Produce a cleaned version of the SAME text in the SAME language:
    - Fix capitalization and punctuation.
    - Remove speech filler words (um, uh, er, ah, hmm, äh, ähm, "you know", "I mean").
    - Fix obvious spacing and minor grammar slips from dictation.
    Do NOT translate, summarize, rephrase, answer, explain, or add or remove any other words. Never write any preamble, commentary, or explanation — only the cleaned text itself.
    """
    #endif

    /// Belt-and-suspenders: if a small model still prepends a commentary line before
    /// a blank line (e.g. "Here is the cleaned text:\n\n…"), drop it. Conservative —
    /// only fires on a short, comment-looking head.
    static func stripPreamble(_ s: String) -> String {
        guard let sep = s.range(of: "\n\n") else { return s }
        let head = String(s[..<sep.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = head.lowercased()
        let markers = ["here is", "here's", "hier ist", "i have", "i've", "ich habe",
                       "the cleaned", "der gereinigte", "sure", "okay", "gerne", "of course"]
        let looksLikeComment = head.count < 140 && (head.hasSuffix(":") || markers.contains { lower.hasPrefix($0) })
        guard looksLikeComment else { return s }
        let tail = String(s[sep.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return tail.isEmpty ? s : tail
    }

    /// Unambiguous spoken fillers (DE + EN). Deliberately conservative: words that
    /// double as real words in context — "like", "well", "so", German "also"/"er" —
    /// are NOT listed, because removing them safely needs sentence understanding
    /// (the `.ai` mode). Rules therefore never change meaning.
    private static let fillers: Set<String> = [
        "um", "uh", "uhm", "umm", "erm", "hmm", "mmm",
        "äh", "ähm", "ähhm", "öh", "öhm", "ähem",
    ]

    /// Pure rule-based cleanup — instant, dependency-free, unit-tested. Drops only
    /// unambiguous filler tokens, collapses whitespace, tidies spacing before
    /// punctuation, and capitalizes sentence starts. Never changes the words.
    static func deterministicCleanup(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let words = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
        var kept: [Substring] = []
        for w in words {
            // Match ignoring case + any attached punctuation (e.g. "um," / "äh.").
            let core = w.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",.!?;:"))
            if fillers.contains(core) { continue }
            kept.append(w)
        }
        var result = kept.joined(separator: " ")

        // Collapse double spaces left by removals + tidy a stray space before punctuation.
        while result.contains("  ") { result = result.replacingOccurrences(of: "  ", with: " ") }
        for p in [",", ".", "!", "?", ";", ":"] {
            result = result.replacingOccurrences(of: " \(p)", with: p)
        }

        result = capitalizingSentences(result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Capitalize the first letter of the text and the first letter after each
    /// sentence terminator (. ! ?). Whitespace is transparent; everything else as-is.
    static func capitalizingSentences(_ text: String) -> String {
        var chars = Array(text)
        var capitalizeNext = true
        for i in chars.indices {
            let c = chars[i]
            if c.isWhitespace { continue }
            if capitalizeNext, c.isLetter {
                let up = String(c).uppercased()
                if up.count == 1, let first = up.first { chars[i] = first }
                capitalizeNext = false
            } else if c == "." || c == "!" || c == "?" {
                capitalizeNext = true
            } else {
                capitalizeNext = false
            }
        }
        return String(chars)
    }
}
