import XCTest
@testable import Stenote

/// Covers the footer's lifetime-duration formatting (minutes / decimal hours).
@MainActor
final class StatFormatTests: XCTestCase {
    private func d(_ s: TimeInterval) -> String { StatFormat.totalDuration(s) }

    func testMinutesUnderAnHour() {
        XCTAssertEqual(d(17 * 60), "17 minutes")
        XCTAssertEqual(d(59 * 60), "59 minutes")
        XCTAssertEqual(d(0), "0 minutes")
    }

    func testRoundsSecondsToWholeMinutes() {
        XCTAssertEqual(d(17 * 60 + 20), "17 minutes")   // 17m20s → 17
        XCTAssertEqual(d(17 * 60 + 40), "18 minutes")   // 17m40s → 18
    }

    func testSingularMinute() {
        XCTAssertEqual(d(60), "1 minute")
    }

    func testWholeHours() {
        XCTAssertEqual(d(60 * 60), "1 hour")
        XCTAssertEqual(d(120 * 60), "2 hours")
    }

    func testDecimalHoursUseGermanComma() {
        XCTAssertEqual(d(90 * 60), "1,5 hours")
        XCTAssertEqual(d(150 * 60), "2,5 hours")
    }

    func testHourBoundary() {
        XCTAssertEqual(d(59 * 60), "59 minutes")
        XCTAssertEqual(d(60 * 60), "1 hour")
    }
}
