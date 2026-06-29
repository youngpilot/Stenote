import XCTest
@testable import Steneo

/// Guards the v0.8.6 fix: the assembled streaming window
/// (leftContext + chunk + rightContext) must NEVER exceed the encoder's fixed
/// input cap. If it does, FluidAudio silently drops the chunk and the middle of
/// long recordings vanishes. These tests make that regression impossible to
/// reintroduce by re-tuning the knobs.
@MainActor
final class StreamingWindowTests: XCTestCase {
    typealias Window = TranscriptionService.StreamingWindow

    func testDefaultWindowFitsCap() {
        let w = Window.clamped()
        XCTAssertLessThanOrEqual(w.windowSeconds, w.capSeconds + 1e-9)
    }

    func testDefaultsMatchTunedValues() {
        // The shipping configuration: chunk 11s, right 1.5s, left 2.0s = 14.5s == cap.
        let w = Window.clamped()
        XCTAssertEqual(w.chunkSeconds, 11.0, accuracy: 1e-9)
        XCTAssertEqual(w.rightContextSeconds, 1.5, accuracy: 1e-9)
        XCTAssertEqual(w.leftContextSeconds, 2.0, accuracy: 1e-9)
        XCTAssertEqual(w.windowSeconds, 14.5, accuracy: 1e-9)
    }

    /// The invariant must hold for any knob values a future tuning pass might pick.
    func testInvariantHoldsAcrossWideKnobRange() {
        for chunk in stride(from: 1.0, through: 30.0, by: 0.5) {
            for left in stride(from: 0.0, through: 10.0, by: 0.5) {
                for right in stride(from: 0.0, through: 5.0, by: 0.5) {
                    for cap in [10.0, 12.0, 14.5, 15.0] {
                        let w = Window.clamped(desiredChunk: chunk,
                                               desiredLeftContext: left,
                                               rightContext: right,
                                               cap: cap)
                        XCTAssertLessThanOrEqual(
                            w.windowSeconds, cap + 1e-9,
                            "window \(w.windowSeconds) exceeded cap \(cap) "
                            + "(chunk=\(chunk) left=\(left) right=\(right))")
                        XCTAssertGreaterThanOrEqual(w.chunkSeconds, 0)
                        XCTAssertGreaterThanOrEqual(w.leftContextSeconds, 0)
                    }
                }
            }
        }
    }

    /// When right context alone fills the cap, the other knobs clamp to 0 rather
    /// than going negative.
    func testKnobsNeverNegative() {
        let w = Window.clamped(desiredChunk: 20, desiredLeftContext: 5, rightContext: 5, cap: 14.5)
        XCTAssertGreaterThanOrEqual(w.leftContextSeconds, 0)
        XCTAssertGreaterThanOrEqual(w.chunkSeconds, 0)
        XCTAssertLessThanOrEqual(w.windowSeconds, 14.5 + 1e-9)
    }
}
