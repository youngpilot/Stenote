import Foundation
import Observation

struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let text: String
    let duration: TimeInterval?

    init(text: String, duration: TimeInterval? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.text = text
        self.duration = duration
    }
}

@Observable
@MainActor
final class HistoryService {
    static let shared = HistoryService()

    private(set) var entries: [HistoryEntry] = []
    private let maxEntries = 10
    private let storageKey = "transcriptionHistory"

    private init() {
        loadFromDefaults()
    }

    func addEntry(_ text: String, duration: TimeInterval? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let entry = HistoryEntry(text: trimmed, duration: duration)
        entries.insert(entry, at: 0)

        // Keep only the last maxEntries
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }

        saveToDefaults()
    }

    func clearHistory() {
        entries = []
        saveToDefaults()
    }

    private func loadFromDefaults() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            entries = try JSONDecoder().decode([HistoryEntry].self, from: data)
        } catch {
            entries = []
        }
    }

    private func saveToDefaults() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
