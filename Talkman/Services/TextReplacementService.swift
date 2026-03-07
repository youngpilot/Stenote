import Foundation
import Observation

@Observable
@MainActor
final class TextReplacementService {
    static let shared = TextReplacementService()

    private let storageKey = "textReplacements"

    /// Maps lowercased phonetic/ASR output → correct brand name
    /// e.g. "antropic" → "Anthropic", "open ai" → "OpenAI"
    /// Empty key = boost-only (no regex replacement)
    private(set) var replacements: [String: String] = [:]

    /// Brand names added without a "wrong" form — boost only, no regex
    private(set) var boostWords: [String] = []

    private let boostStorageKey = "boostWords"

    private init() {
        load()
    }

    func addReplacement(from: String, to: String) {
        replacements[from.lowercased()] = to
        save()
    }

    func addBoostWord(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !boostWords.contains(trimmed) else { return }
        boostWords.append(trimmed)
        saveBoostWords()
    }

    func removeReplacement(from: String) {
        replacements.removeValue(forKey: from.lowercased())
        save()
    }

    func removeBoostWord(_ word: String) {
        boostWords.removeAll { $0 == word }
        saveBoostWords()
    }

    func removeAll() {
        replacements = [:]
        boostWords = []
        save()
        saveBoostWords()
    }

    func applyReplacements(to text: String) -> String {
        guard !replacements.isEmpty else { return text }

        var result = text
        // Sort by length descending so longer matches take priority
        let sorted = replacements.sorted { $0.key.count > $1.key.count }

        for (pattern, replacement) in sorted {
            // Case-insensitive word-boundary replacement
            // Using regex for proper word boundary matching
            let escaped = NSRegularExpression.escapedPattern(for: pattern)
            guard let regex = try? NSRegularExpression(
                pattern: "\\b\(escaped)\\b",
                options: .caseInsensitive
            ) else { continue }

            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: replacement
            )
        }

        return result
    }

    // MARK: - Persistence

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            replacements = decoded
        }
        if let data = UserDefaults.standard.data(forKey: boostStorageKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            boostWords = decoded
        }
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(replacements), forKey: storageKey)
    }

    private func saveBoostWords() {
        UserDefaults.standard.set(try? JSONEncoder().encode(boostWords), forKey: boostStorageKey)
    }
}
