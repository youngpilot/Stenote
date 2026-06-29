import XCTest
@testable import Stenote

/// Covers the ASR trailing-stutter cleanup that runs on the final transcript.
@MainActor
final class StutterRemovalTests: XCTestCase {
    private func strip(_ s: String) -> String {
        TranscriptionService.removeTrailingStutter(s)
    }

    func testOneWordStutterRemoved() {
        XCTAssertEqual(strip("hello world world"), "hello world")
    }

    func testTwoWordStutterRemoved() {
        XCTAssertEqual(strip("that is great is great"), "that is great")
    }

    func testTwoWordStutterTakesPriorityOverOneWord() {
        // Exactly four words "X Y X Y" → drop the repeated pair.
        XCTAssertEqual(strip("is great is great"), "is great")
    }

    func testNoStutterIsUnchanged() {
        XCTAssertEqual(strip("hello world"), "hello world")
        XCTAssertEqual(strip("the quick brown fox"), "the quick brown fox")
    }

    func testShortRepeatIsKept() {
        // Guard against false positives on tiny words like "I I" / "go go".
        XCTAssertEqual(strip("I go go"), "I go go")
    }

    func testProperNounRepeatIsKept() {
        // Capitalised repeats are likely intentional ("New York, New York").
        XCTAssertEqual(strip("New York New York"), "New York New York")
    }

    func testStutterRemovedIgnoringPunctuationAndCase() {
        XCTAssertEqual(strip("see you tomorrow Tomorrow"), "see you tomorrow")
    }

    func testEmptyAndSingleWord() {
        XCTAssertEqual(strip(""), "")
        XCTAssertEqual(strip("hello"), "hello")
    }

    // MARK: - Incremental-segmentation assembly

    func testAssembleSegments() {
        XCTAssertEqual(
            TranscriptionService.assembleSegments(["First part.", "Second part."], tail: "And the end."),
            "First part. Second part. And the end.")
        // No cut fired → just the tail (= whole recording).
        XCTAssertEqual(
            TranscriptionService.assembleSegments([], tail: "just the whole thing"),
            "just the whole thing")
        // Empty pieces (failed/blank segment, or a silence-only tail) are dropped.
        XCTAssertEqual(
            TranscriptionService.assembleSegments(["a", "", "c"], tail: "d"),
            "a c d")
        XCTAssertEqual(
            TranscriptionService.assembleSegments(["only segment"], tail: ""),
            "only segment")
        XCTAssertEqual(TranscriptionService.assembleSegments([], tail: ""), "")
    }
}
