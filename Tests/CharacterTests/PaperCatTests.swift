import PaperCatBehavior
import PopupBookCore
import XCTest

final class PaperCatTests: XCTestCase {
    struct Harness {
        var fold = FoldState(), cat = PaperCat()
        var context = WorldContext(progress: 1, clock: 0, deltaTime: 0, stableDuration: 0)
        mutating func advance(_ seconds: Double) -> [SoundID] {
            var sounds: [SoundID] = []
            for _ in 0..<Int(seconds * 120) {
                context = fold.advance(1.0 / 120)
                sounds += cat.advance(in: context).sounds
            }
            return sounds
        }
    }
    func testWakeWalkGreetAndSingleSound() {
        var h = Harness()
        _ = h.advance(5)
        XCTAssertEqual(h.cat.pose.mood, .resting)
        XCTAssertEqual(h.cat.pose.outside, 1)
        XCTAssertTrue(h.cat.interact(.greet, in: h.context))
        XCTAssertFalse(h.cat.interact(.greet, in: h.context))
        XCTAssertEqual(h.advance(1.3), [SoundID("paper-cat.greeting")])
        XCTAssertEqual(h.cat.pose.mood, .resting)
    }
    func testHalfOpenWaitDoesNotTriggerExit() {
        var h = Harness()
        h.fold.target = 0.5
        _ = h.advance(6)
        XCTAssertEqual(h.cat.pose.outside, 0)
        XCTAssertEqual(h.cat.pose.mood, .waking)
    }

    func testPresenceEventsAreNotRepeatedEveryFrame() {
        var fold = FoldState()
        var cat = PaperCat()
        var exits = 0
        for _ in 0..<1200 {
            let output = cat.advance(in: fold.advance(1.0 / 120))
            exits += output.events.filter { $0 == .outside }.count
        }
        XCTAssertEqual(exits, 1)
    }

    func testInterruptionReverseAndTenCycles() {
        var h = Harness()
        _ = h.advance(5)
        _ = h.cat.interact(.greet, in: h.context)
        h.fold.target = 0.6
        _ = h.advance(0.25)
        XCTAssertEqual(h.cat.pose.mood, .returning)
        let previous = h.cat.pose.outside
        h.fold.target = 1
        _ = h.advance(1.0 / 120)
        XCTAssertLessThan(abs(previous - h.cat.pose.outside), 0.1)
        _ = h.advance(4)
        XCTAssertEqual(h.cat.pose.mood, .resting)
        for _ in 0..<10 {
            h.fold.target = 0
            _ = h.advance(1)
            XCTAssertEqual(h.cat.pose.mood, .sleeping)
            XCTAssertEqual(h.cat.pose.outside, 0)
            XCTAssertFalse(h.cat.interact(.greet, in: h.context))
            h.fold.target = 1
            _ = h.advance(5)
            XCTAssertEqual(h.cat.pose.mood, .resting)
            XCTAssertEqual(h.cat.pose.outside, 1)
        }
    }
}
