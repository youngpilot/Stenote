import XCTest
@testable import Stenote

/// Covers per-recording WPM eligibility + word counting (the stat shown as an
/// average in the footer). The average itself is computed on HistoryService
/// (a @MainActor singleton over real storage) and isn't unit-tested here.
@MainActor
final class WPMTests: XCTestCase {
    private func entry(_ text: String, duration: TimeInterval?, wordCount: Int? = nil) -> HistoryEntry {
        HistoryEntry(text: text, duration: duration, recordingId: 1, wordCount: wordCount)
    }

    func testWordCount() {
        XCTAssertEqual("hello world".stenoteWordCount, 2)
        XCTAssertEqual("  hello   world  ".stenoteWordCount, 2)   // extra whitespace dropped
        XCTAssertEqual("one\ntwo\tthree".stenoteWordCount, 3)     // newlines + tabs split
        XCTAssertEqual("".stenoteWordCount, 0)
        XCTAssertEqual("Hello, world!".stenoteWordCount, 2)        // punctuation stays attached
    }

    func testBasicWPM() {
        let words = Array(repeating: "word", count: 30).joined(separator: " ")
        XCTAssertEqual(entry(words, duration: 30, wordCount: 30).wpm!, 60, accuracy: 0.001)
    }

    func testFileImportHasNoWPM() {
        XCTAssertNil(entry("plenty of words here for sure indeed", duration: nil, wordCount: 7).wpm)
    }

    func testTooShortDurationExcluded() {
        XCTAssertNil(entry("five words right here now", duration: 2.0, wordCount: 5).wpm)
    }

    func testTooFewWordsExcluded() {
        XCTAssertNil(entry("hi there", duration: 10, wordCount: 2).wpm)
    }

    func testImplausiblyFastExcluded() {
        // 500 words in 10s = 3000 wpm → garbage, excluded by the <=400 guard.
        XCTAssertNil(entry("x", duration: 10, wordCount: 500).wpm)
    }

    func testImplausiblySlowExcluded() {
        // 5 words over 600s = 0.5 wpm (mic left on through silence) → excluded.
        XCTAssertNil(entry("one two three four five", duration: 600, wordCount: 5).wpm)
    }

    func testLegacyEntryBackfillsWordCountFromText() {
        let words = Array(repeating: "word", count: 20).joined(separator: " ")
        XCTAssertEqual(entry(words, duration: 20, wordCount: nil).wpm!, 60, accuracy: 0.001)
    }

    func testThresholdBoundariesAreInclusive() {
        XCTAssertNotNil(entry("one two three four five", duration: 3.0, wordCount: 5).wpm)  // 3s / 5 words
        XCTAssertEqual(entry("x", duration: 3.0, wordCount: 20).wpm!, 400, accuracy: 0.001) // exactly 400
    }
}
