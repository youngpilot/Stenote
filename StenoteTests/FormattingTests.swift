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

    func testNoneModeIsPassThrough() async {
        let s = "this is left exactly as it is"
        let out = await FormattingService.shared.format(s, mode: .none)
        XCTAssertEqual(out, s)
        let blank = await FormattingService.shared.format("   ", mode: .bullets)
        XCTAssertEqual(blank, "   ")
    }

    /// Integration smoke test — runs the REAL on-device model. Skipped when Apple
    /// Intelligence is unavailable (CI / unsupported Mac). Verifies the format path
    /// produces sane, structured output end-to-end; it is NOT a quality judgment.
    func testFormattingIntegrationSmoke() async throws {
        try XCTSkipUnless(
            FormattingService.shared.usesAppleIntelligence,
            "Apple Intelligence unavailable — skipping on-device formatting smoke test")
        let svc = FormattingService.shared
        let sample = "okay so first we need to buy milk then we should call the bank and also book the train tickets for friday morning"

        let bullets = await svc.format(sample, mode: .bullets)
        XCTAssertFalse(bullets.isEmpty)
        XCTAssertLessThanOrEqual(bullets.count, sample.count * 3)
        // If the model actually ran (didn't fall back to raw input), bullets carry the glyph.
        if bullets != sample {
            XCTAssertTrue(bullets.contains("•"), "bullets output was: \(bullets)")
        }

        let paragraphs = await svc.format(sample, mode: .paragraphs)
        XCTAssertFalse(paragraphs.isEmpty)
        XCTAssertLessThanOrEqual(paragraphs.count, sample.count * 3)
    }
}
