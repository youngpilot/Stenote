import XCTest
@testable import Stenote

/// Tests for the pure (non-LLM) helpers of FormattingService. The Foundation
/// Models path needs the on-device model and isn't unit-tested here.
@MainActor
final class FormattingTests: XCTestCase {
    func testRenderBullets() {
        XCTAssertEqual(
            FormattingService.renderBullets(["first", "second"]),
            "• first\n• second")
        XCTAssertEqual(FormattingService.renderBullets(["only"]), "• only")
        XCTAssertEqual(FormattingService.renderBullets([]), "")
    }

    func testSaneRejectsEmptyAndOverlong() {
        XCTAssertTrue(FormattingService.sane("Hello there.", against: "hello there"))
        XCTAssertFalse(FormattingService.sane("", against: "hello"))
        // Wildly longer than the input = likely added commentary → rejected.
        let bloated = String(repeating: "x", count: 500)
        XCTAssertFalse(FormattingService.sane(bloated, against: "hi"))
    }

    func testFormatModeLabels() {
        XCTAssertEqual(FormatMode.none.label, "None")
        XCTAssertEqual(FormatMode.paragraphs.label, "Paragraphs")
        XCTAssertEqual(FormatMode.bullets.label, "Bullets")
        XCTAssertEqual(FormatMode.allCases.count, 3)
    }
}
