import XCTest

@testable import PopupBookCore

final class FoldTests: XCTestCase {
    func testMappingAndInvalidData() {
        for (a, p) in [(0.0, 0.0), (35, 0), (70, 0.5), (105, 1), (180, 1)] {
            XCTAssertEqual(FoldState.openness(angle: a), p)
        }
        for a in [Double.nan, .infinity, -1, 181] { XCTAssertNil(FoldState.openness(angle: a)) }
        XCTAssertNil(FoldState.openness(angle: 90, full: 35))
    }
    func testCalibrationAndNoOvershoot() {
        var fold = FoldState()
        XCTAssertFalse(fold.calibrate(79))
        XCTAssertTrue(fold.calibrate(80))
        XCTAssertTrue(fold.calibrate(120))
        XCTAssertFalse(fold.calibrate(.nan))
        fold.target = 0
        var last = fold.progress
        for _ in 0..<120 {
            let c = fold.advance(1.0 / 120)
            XCTAssertLessThanOrEqual(c.progress, last)
            XCTAssertGreaterThanOrEqual(c.progress, 0)
            last = c.progress
        }
        fold.target = 0.9
        for _ in 0..<720 { _ = fold.advance(1.0 / 120) }
        XCTAssertEqual(fold.progress, 0.9, accuracy: 0.001)
    }
    func testLossRecoveryAndOutOfOrderSamples() {
        var fold = FoldState()
        fold.receive(AngleSample(angle: 90, timestamp: 1))
        let p = fold.target
        fold.receive(AngleSample(angle: nil, timestamp: 1.1))
        XCTAssertTrue(fold.sensorAvailable)
        fold.receive(AngleSample(angle: nil, timestamp: 2.2))
        XCTAssertFalse(fold.sensorAvailable)
        XCTAssertEqual(fold.target, p)
        fold.receive(AngleSample(angle: 70, timestamp: 2.3))
        XCTAssertTrue(fold.sensorAvailable)
        XCTAssertEqual(fold.target, 0.5)
        fold.receive(AngleSample(angle: 100, timestamp: 1))
        XCTAssertEqual(fold.target, 0.5)
    }
}
