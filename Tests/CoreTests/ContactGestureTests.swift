import PopupBookCore
import XCTest

final class ContactGestureTests: XCTestCase {
    func testShortClickAndLongDragAreExclusive() {
        var gesture = ContactGesture()
        XCTAssertEqual(gesture.begin(x: 0, y: 0, time: 1, point: .center), [.contactBegan(.center)])
        XCTAssertEqual(gesture.end(time: 1.2), [.contactEnded, .greet])
        _ = gesture.begin(x: 0, y: 0, time: 2, point: .center)
        let moved = gesture.move(x: 20, y: 0, time: 2.2, point: .center)
        guard case .contactMoved(_, let strength) = moved.first else { return XCTFail("应产生接触更新") }
        XCTAssertEqual(strength, 1, accuracy: 0.00001)
        XCTAssertEqual(gesture.end(time: 2.25), [.contactEnded])
        XCTAssertEqual(gesture.end(time: 3), [])
    }
    func testExcessSpeedAndCancellationNeverBecomeClick() {
        var gesture = ContactGesture()
        _ = gesture.begin(x: 0, y: 0, time: 0, point: .center)
        XCTAssertEqual(
            gesture.move(x: 100, y: 0, time: 0.01, point: .center), [.contactMoved(.center, intensity: 0)])
        XCTAssertEqual(gesture.cancel(), [.contactEnded])
        XCTAssertFalse(gesture.isActive)
        XCTAssertEqual(gesture.end(time: 0.2), [])
        XCTAssertEqual(gesture.begin(x: .nan, y: 0, time: 0, point: .center), [])
        XCTAssertEqual(ContactPoint(x: .infinity, y: -4), ContactPoint(x: 0.5, y: 0))
    }
    func testFixedSeedIsReproducibleAndBounded() {
        var a = SeededRandom(seed: 234)
        var b = SeededRandom(seed: 234)
        for _ in 0..<1000 {
            let value = a.nextUnit()
            XCTAssertEqual(value, b.nextUnit())
            XCTAssertTrue((0..<1).contains(value))
        }
    }
}
