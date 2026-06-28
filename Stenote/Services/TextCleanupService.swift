import Foundation
import os
#if canImport(FoundationModels)
import FoundationModels
#endif

private let logger = Logger(subsystem: "com.youngpilot.Stenote", category: "TextCleanup")

/// On-device cleanup of dictated text. Uses Apple's on-device Foundation Models
/// when available (macOS 26+, Apple Intelligence enabled); otherwise a
/// deterministic, rule-based fallback. Everything runs on-device — text never
/// leaves the Mac, preserving Steneo's privacy guarantee (the whole reason this
/// uses Apple's local model instead of a cloud LLM).
@MainActor
final class TextCleanupService {
    static let shared = TextCleanupService()
    private init() {}

    /// True when the Apple Foundation Models on-device LLM can be used. False on
    /// older macOS or when Apple Intelligence is off / not yet ready → the
    /// deterministic fallback is used instead.
    var usesAppleIntelligence: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    /// Clean up `text`. Never throws: on any failure it returns the deterministic
    /// result, or the original text. Safe to call regardless of OS / availability.
    func cleanup(_ text: String) async -> String {
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
        let session = LanguageModelSession(instructions: Self.instructions)
        // Greedy = deterministic; bound the output so the model can't ramble off
        // into commentary on long inputs.
        let options = GenerationOptions(
            sampling: .greedy,
            maximumResponseTokens: min(2000, max(128, text.count)))
        do {
            let response = try await session.respond(to: text, options: options)
            let cleaned = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            // Reject obvious misfires (empty, or wildly longer than the input —
            // a sign it added commentary) and fall back to deterministic instead.
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
    You are a text cleanup tool for dictated speech. Given raw dictated text, return a cleaned version of the SAME text:
    - Fix capitalization and punctuation.
    - Remove speech filler words (um, uh, er, ah, hmm, äh, ähm, "you know", "I mean").
    - Fix obvious spacing and minor grammar slips from dictation.
    Strict rules: keep the original language. Do NOT translate, summarize, rephrase, answer, explain, or add ANY new words or commentary. Preserve the speaker's wording and meaning. Output ONLY the cleaned text and nothing else.
    """
    #endif

    /// Deterministic, dependency-free cleanup for when the on-device model isn't
    /// available. Conservative by design (it can't "understand" the text): it
    /// collapses whitespace, drops only unambiguous filler tokens, tidies spacing
    /// before punctuation, and capitalizes sentence starts. Pure → unit-tested.
    static func deterministicCleanup(_ text: String) -> String {
        // Unambiguous fillers only — never real words like "like"/"er" that carry
        // meaning (German "er" = he), so we can't change what was said.
        let fillers: Set<String> = ["um", "uh", "uhm", "umm", "hmm", "äh", "ähm", "ähhm", "öhm"]

        let words = text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
        var kept: [Substring] = []
        for w in words {
            let core = w.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",."))
            if fillers.contains(core) { continue }
            kept.append(w)
        }
        var result = kept.joined(separator: " ")

        // Collapse any double spaces left behind by removals.
        while result.contains("  ") { result = result.replacingOccurrences(of: "  ", with: " ") }
        // Tidy a stray space before punctuation.
        for p in [",", ".", "!", "?", ";", ":"] {
            result = result.replacingOccurrences(of: " \(p)", with: p)
        }

        result = capitalizingSentences(result)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Capitalize the first letter of the text and the first letter after each
    /// sentence terminator (. ! ?). Whitespace is transparent; everything else is
    /// left as-is.
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
