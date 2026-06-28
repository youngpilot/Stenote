import XCTest
@testable import Stenote

/// Tests for the deterministic (non-AI) cleanup path — the rule-based fallback
/// used when Apple Foundation Models isn't available. The Foundation Models path
/// needs the on-device model and isn't unit-tested here.
@MainActor
final class TextCleanupTests: XCTestCase {
    func testRemovesFillerWords() {
        XCTAssertEqual(TextCleanupService.deterministicCleanup("um hello uh world"), "Hello world")
    }

    func testKeepsRealWordsLikeAndGermanEr() {
        // "like" and German "er" (= he) carry meaning — must never be dropped.
        XCTAssertEqual(TextCleanupService.deterministicCleanup("I like it"), "I like it")
        XCTAssertEqual(TextCleanupService.deterministicCleanup("er ähm geht"), "Er geht")
    }

    func testCapitalizesSentences() {
        XCTAssertEqual(
            TextCleanupService.deterministicCleanup("hello. world! how are you?"),
            "Hello. World! How are you?")
    }

    func testCollapsesWhitespace() {
        XCTAssertEqual(TextCleanupService.deterministicCleanup("hello    world"), "Hello world")
    }

    func testTrimsSpaceBeforePunctuation() {
        XCTAssertEqual(TextCleanupService.deterministicCleanup("hello , world ."), "Hello, world.")
    }

    func testFillerWithTrailingComma() {
        XCTAssertEqual(TextCleanupService.deterministicCleanup("well um, that works"), "Well that works")
    }

    func testEmptyAndWhitespaceOnly() {
        XCTAssertEqual(TextCleanupService.deterministicCleanup(""), "")
        XCTAssertEqual(TextCleanupService.deterministicCleanup("   "), "")
    }

    func testAlreadyCleanTextUnchanged() {
        XCTAssertEqual(
            TextCleanupService.deterministicCleanup("This is already clean."),
            "This is already clean.")
    }

    func testCapitalizingSentencesIdempotent() {
        let s = "Hello world. This is fine."
        XCTAssertEqual(TextCleanupService.capitalizingSentences(s), s)
    }

    func testRemovesExpandedAndRepeatedFillers() {
        XCTAssertEqual(TextCleanupService.deterministicCleanup("erm okay, öhm done"), "Okay, done")
        XCTAssertEqual(TextCleanupService.deterministicCleanup("uh uh hello"), "Hello")
    }
}
