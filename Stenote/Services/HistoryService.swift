import Foundation
import Observation
import os

private let logger = Logger(subsystem: "com.youngpilot.Stenote", category: "History")

struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let text: String
    let duration: TimeInterval?
    let recordingId: Int?

    init(text: String, duration: TimeInterval? = nil, recordingId: Int? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.text = text
        self.duration = duration
        self.recordingId = recordingId
    }

    var formattedId: String {
        String(format: "%05d", recordingId ?? 0)
    }
}

@Observable
@MainActor
final class HistoryService {
    static let shared = HistoryService()

    private(set) var entries: [HistoryEntry] = []
    private(set) var totalRecordings: Int = 0
    private(set) var totalDuration: TimeInterval = 0
    private(set) var totalCharacters: Int = 0
    private let storageKey = "transcriptionHistory"          // legacy plaintext (migrated away)
    private let encStorageKey = "transcriptionHistory.enc"   // AES-GCM ciphertext at rest

    private init() {
        loadFromDefaults()
        let ud = UserDefaults.standard
        totalRecordings = ud.integer(forKey: "totalRecordings")
        totalDuration = ud.double(forKey: "totalDuration")
        totalCharacters = ud.integer(forKey: "totalCharacters")
    }

    func addEntry(_ text: String, duration: TimeInterval? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        totalRecordings += 1
        let entry = HistoryEntry(text: trimmed, duration: duration, recordingId: totalRecordings)
        entries.insert(entry, at: 0)

        if let cap = SettingsStore.shared.historyLength.cap, entries.count > cap {
            entries = Array(entries.prefix(cap))
        }

        // Update lifetime stats
        totalCharacters += trimmed.count
        if let d = duration { totalDuration += d }
        let ud = UserDefaults.standard
        ud.set(totalRecordings, forKey: "totalRecordings")
        ud.set(totalDuration, forKey: "totalDuration")
        ud.set(totalCharacters, forKey: "totalCharacters")

        saveToDefaults()
    }

    func deleteEntry(_ id: UUID) {
        entries.removeAll { $0.id == id }
        saveToDefaults()
    }

    func clearHistory() {
        entries = []
        saveToDefaults()
    }

    /// Trim stored entries to the current history-length setting. Call when the
    /// setting changes (e.g. user lowers the limit or picks None).
    func enforceLimit() {
        guard let cap = SettingsStore.shared.historyLength.cap else { return }
        if entries.count > cap {
            entries = Array(entries.prefix(cap))
            saveToDefaults()
        }
    }

    /// Load the encrypted history, migrating a legacy plaintext store on first run.
    private func loadFromDefaults() {
        let ud = UserDefaults.standard

        // Preferred path: the encrypted store.
        if let blob = ud.data(forKey: encStorageKey) {
            if let plain = EncryptionService.shared.decrypt(blob),
               let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: plain) {
                entries = decoded
            } else {
                // Key lost or data tampered — start clean rather than crash.
                logger.error("History unreadable; starting empty")
                entries = []
            }
            return
        }

        // One-time migration: legacy plaintext → encrypted, then drop the plaintext.
        if let legacy = ud.data(forKey: storageKey) {
            entries = (try? JSONDecoder().decode([HistoryEntry].self, from: legacy)) ?? []
            saveToDefaults()
            ud.removeObject(forKey: storageKey)
            logger.info("Migrated \(self.entries.count) history entries to encrypted storage")
        }
    }

    /// Persist the history encrypted at rest (AES-GCM, key in the Keychain).
    private func saveToDefaults() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        guard let blob = EncryptionService.shared.encrypt(data) else {
            logger.error("History not saved: encryption unavailable")
            return
        }
        UserDefaults.standard.set(blob, forKey: encStorageKey)
    }
}
