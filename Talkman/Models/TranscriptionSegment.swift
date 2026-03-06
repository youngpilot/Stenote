import Foundation

struct TranscriptionSegment: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let timestamp: Date
    let language: String?
    let isFinal: Bool
}
