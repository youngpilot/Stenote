import Foundation

/// On-device, rule-based cleanup of dictated text: removes spoken filler words and
/// tidies spacing/capitalization. Fast, deterministic, and NEVER changes the actual
/// wording or meaning — so it's safe in any language (no LLM "normalization").
///
/// The speech model (Parakeet) already produces punctuation and capitalization, so
/// filler removal is the only real job here. Smart formatting — paragraphs, bullet
/// lists, "→ email / Slack", tone — genuinely needs an on-device LLM (Apple
/// Foundation Models) and is a separate, planned feature; it's intentionally NOT
/// done here so basic cleanup stays instant and risk-free.
@MainActor
final class TextCleanupService {
    static let shared = TextCleanupService()
    private init() {}

    /// Remove spoken fillers + tidy spacing/capitalization. Instant; never alters
    /// the actual words. Blank input yields an empty string.
    func cleanup(_ text: String) -> String {
        Self.deterministicCleanup(text)
    }

    /// Unambiguous spoken fillers (DE + EN). Deliberately conservative: words that
    /// double as real words in context — "like", "well", "so", German "also"/"er" —
    /// are NOT listed, because removing them safely needs sentence understanding
    /// (the future opt-in LLM "aggressive" mode). Rules therefore never change meaning.
    private static let fillers: Set<String> = [
        "um", "uh", "uhm", "umm", "erm", "hmm", "mmm",
        "äh", "ähm", "ähhm", "öh", "öhm", "ähem",
    ]

    /// Pure rule-based cleanup — unit-tested.
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
