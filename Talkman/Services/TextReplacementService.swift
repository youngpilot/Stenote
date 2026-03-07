import Foundation
import Observation

@Observable
@MainActor
final class TextReplacementService {
    static let shared = TextReplacementService()

    private let storageKey = "textReplacements"

    /// Maps lowercased phonetic/ASR output → correct brand name
    /// e.g. "antropic" → "Anthropic", "open ai" → "OpenAI"
    private(set) var replacements: [String: String] = [:]

    private init() {
        load()
    }

    func addReplacement(from: String, to: String) {
        replacements[from.lowercased()] = to
        save()
    }

    func removeReplacement(from: String) {
        replacements.removeValue(forKey: from.lowercased())
        save()
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
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        replacements = decoded
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(replacements), forKey: storageKey)
    }
}
