import Foundation
import PopupBookCore
import XCTest

@testable import PaperCatBehavior

private struct Simulation {
    var cat: PaperCat
    var context = WorldContext(progress: 1, clock: 0, deltaTime: 1.0 / 60, stableDuration: 0)
    init(seed: UInt64 = 42) {
        cat = PaperCat(random: SeededRandom(seed: seed))
        cat.sessionBegan(at: Date(timeIntervalSince1970: 0))
    }
    mutating func step(progress: Double = 1) -> CharacterOutput<CatPose> {
        context.progress = progress
        context.clock += 1.0 / 60
        context.stableDuration += 1.0 / 60
        return cat.advance(in: context)
    }
    mutating func run(_ seconds: Double, progress: Double = 1) {
        for _ in 0..<Int(seconds * 60) { _ = step(progress: progress) }
    }
}

final class CompanionshipTests: XCTestCase {
    func testInvitationAcknowledgesImmediatelyAndAlwaysStartsApproachWhenAvailable() {
        for seed in 0..<20 {
            var simulation = Simulation(seed: UInt64(seed))
            simulation.run(5)
            XCTAssertTrue(simulation.cat.interact(.invite(.invitation), in: simulation.context))
            XCTAssertEqual(simulation.cat.pose.mood, .strolling)
            XCTAssertEqual(simulation.cat.pose.acknowledgement, 1)
            simulation.run(0.1)
            XCTAssertGreaterThan(simulation.cat.pose.roaming, 0)
            let elapsed = simulation.cat.pose.moodTime
            let position = simulation.cat.pose.roaming
            XCTAssertTrue(simulation.cat.interact(.invite(.invitation), in: simulation.context))
            XCTAssertEqual(simulation.cat.pose.moodTime, elapsed, "重复邀请不能重启动作")
            XCTAssertEqual(simulation.cat.pose.roaming, position)
            simulation.run(2.2)
            XCTAssertEqual(simulation.cat.pose.roaming, 1, accuracy: 0.001)
            XCTAssertTrue(simulation.cat.interact(.invite(.invitation), in: simulation.context))
            simulation.run(0.2)
            XCTAssertEqual(simulation.cat.pose.roaming, 1, accuracy: 0.001, "已经靠近后不能反而走开")
        }
    }
    func testTouchButtonRespondsImmediatelyAndPhysicalStrokeShowsWithinTwoTenths() {
        var button = Simulation()
        button.run(5)
        XCTAssertTrue(button.cat.interact(.gentleTouch, in: button.context))
        XCTAssertEqual(button.cat.pose.mood, .petting)
        button.run(0.1)
        XCTAssertGreaterThan(button.cat.pose.touchBlend, 0.6)
        var pointer = Simulation()
        pointer.run(5)
        _ = pointer.cat.interact(.contactBegan(.center), in: pointer.context)
        for _ in 0..<12 {
            _ = pointer.cat.interact(.contactMoved(.center, intensity: 0.5), in: pointer.context)
            _ = pointer.step()
        }
        XCTAssertEqual(pointer.cat.pose.mood, .petting)
        XCTAssertGreaterThan(pointer.cat.pose.touchBlend, 0.5)
    }
    func testTenMinutesHaveVarietyAndRemainDeterministic() {
        var a = Simulation(seed: 918)
        var b = Simulation(seed: 918)
        var moods = Set<CatMood>()
        for _ in 0..<36000 {
            let output = a.step()
            let other = b.step()
            moods.insert(output.pose.mood)
            XCTAssertEqual(output.pose.mood, other.pose.mood)
            XCTAssertEqual(output.pose.roaming, other.pose.roaming)
            XCTAssertTrue((0...1).contains(output.pose.outside))
            XCTAssertTrue((0...1).contains(output.pose.roaming))
            XCTAssertTrue((0...1).contains(a.cat.temperament.relaxation))
        }
        XCTAssertGreaterThanOrEqual(
            moods.intersection([.observing, .grooming, .settling, .strolling, .resting, .stretching]).count, 4
        )
    }
    func testGentleTouchRespondsAndStopsWithoutReplay() {
        var simulation = Simulation()
        simulation.run(5)
        XCTAssertTrue(simulation.cat.interact(.gentleTouch, in: simulation.context))
        simulation.run(0.8)
        XCTAssertEqual(simulation.cat.pose.mood, .petting)
        XCTAssertGreaterThan(simulation.cat.pose.touchBlend, 0.5)
        simulation.run(2)
        XCTAssertEqual(simulation.cat.memory.effectiveTouches, 1)
        XCTAssertNotEqual(simulation.cat.pose.mood, .petting)
        simulation.cat.sessionEnded(at: nil)
        simulation.run(0.3)
        XCTAssertLessThan(simulation.cat.pose.touchBlend, 0.3)
    }
    func testPurrBeginsOnceAndFadesWhenFoldInterruptsContact() {
        var simulation = Simulation()
        simulation.run(5)
        _ = simulation.cat.interact(.gentleTouch, in: simulation.context)
        var commands: [SoundCommand] = []
        for _ in 0..<90 { commands += simulation.step().soundCommands }
        XCTAssertEqual(commands, [.beginLoop(PaperCatSounds.purr)])
        let end = simulation.step(progress: 0.6)
        XCTAssertEqual(end.soundCommands, [.endLoop(PaperCatSounds.purr, fade: 0.3)])
        XCTAssertEqual(simulation.cat.pose.mood, .returning)
        XCTAssertTrue(simulation.step(progress: 0.6).soundCommands.isEmpty)
    }
    func testRepeatedGentleTouchDoesNotQueueOrExtendTheAction() {
        var simulation = Simulation()
        simulation.run(5)
        XCTAssertTrue(simulation.cat.interact(.gentleTouch, in: simulation.context))
        simulation.run(1)
        XCTAssertFalse(simulation.cat.interact(.gentleTouch, in: simulation.context))
        simulation.run(1.2)
        XCTAssertNotEqual(simulation.cat.pose.mood, .petting)
        XCTAssertEqual(simulation.cat.memory.effectiveTouches, 1)
    }
    func testPhysicalContactDoesNotInheritTheButtonAutomaticMotion() {
        var simulation = Simulation()
        simulation.run(5)
        _ = simulation.cat.interact(.gentleTouch, in: simulation.context)
        simulation.run(0.8)
        XCTAssertTrue(simulation.cat.interact(.contactBegan(.center), in: simulation.context))
        // A physical pointer is now stationary. It must not inherit generated touch updates.
        simulation.run(1.4)
        XCTAssertNotEqual(simulation.cat.pose.mood, .petting)
        XCTAssertEqual(simulation.cat.memory.effectiveTouches, 0)
    }
    func testInterruptedStrokesDoNotAccumulateIntoOneEffectiveTouch() {
        var simulation = Simulation()
        simulation.run(5)
        _ = simulation.cat.interact(.contactBegan(.center), in: simulation.context)
        for _ in 0..<5 {
            for _ in 0..<60 {
                _ = simulation.cat.interact(.contactMoved(.center, intensity: 0.5), in: simulation.context)
                _ = simulation.step()
            }
            _ = simulation.cat.interact(.contactMoved(.center, intensity: 0), in: simulation.context)
            simulation.run(0.3)
        }
        XCTAssertEqual(simulation.cat.memory.effectiveTouches, 0)
    }
    func testFastMovementDoesNotBecomeEffectiveTouchAndContactCanCancel() {
        var simulation = Simulation()
        simulation.run(5)
        XCTAssertTrue(simulation.cat.interact(.contactBegan(.center), in: simulation.context))
        for _ in 0..<240 {
            _ = simulation.cat.interact(.contactMoved(.center, intensity: 0), in: simulation.context)
            _ = simulation.step()
        }
        XCTAssertEqual(simulation.cat.memory.effectiveTouches, 0)
        XCTAssertNotEqual(simulation.cat.pose.mood, .petting)
        _ = simulation.cat.interact(.contactEnded, in: simulation.context)
        XCTAssertFalse(simulation.cat.interact(.contactMoved(.center, intensity: 1), in: simulation.context))
    }
    func testEveryAutonomousActionCanBeInterruptedByFolding() {
        var simulation = Simulation()
        var covered = Set<CatMood>()
        for _ in 0..<36000 {
            _ = simulation.step()
            let mood = simulation.cat.pose.mood
            if !mood.isInside && mood != .returning && !covered.contains(mood) {
                let before = simulation.cat.pose.outside
                _ = simulation.step(progress: 0.6)
                if before > 0.05 {
                    XCTAssertEqual(simulation.cat.pose.mood, .returning)
                } else {
                    XCTAssertTrue([CatMood.returning, .waking].contains(simulation.cat.pose.mood))
                }
                XCTAssertLessThanOrEqual(abs(before - simulation.cat.pose.outside), 0.2)
                simulation.run(1, progress: 0)
                XCTAssertEqual(simulation.cat.pose.outside, 0)
                simulation.run(5)
                covered.insert(mood)
            }
        }
        XCTAssertTrue(covered.contains(.grooming))
        XCTAssertTrue(covered.contains(.strolling))
    }
    func testMeetingPersistenceAndClockRollback() throws {
        var simulation = Simulation()
        simulation.cat.sessionEnded(at: Date(timeIntervalSince1970: 0))
        simulation.cat.sessionBegan(at: Date(timeIntervalSince1970: 10000))
        simulation.run(65)
        XCTAssertEqual(simulation.cat.memory.meetings, 1)
        let data = try XCTUnwrap(simulation.cat.persistentState)
        var other = Simulation()
        try other.cat.restorePersistentState(data)
        other.cat.sessionEnded(at: Date(timeIntervalSince1970: 0))
        other.cat.sessionBegan(at: Date(timeIntervalSince1970: 9900))
        other.run(65)
        XCTAssertEqual(other.cat.memory.meetings, 1)
        other.cat.sessionEnded(at: Date(timeIntervalSince1970: 9900))
        other.cat.sessionBegan(at: Date(timeIntervalSince1970: 11900))
        other.run(65)
        XCTAssertEqual(other.cat.memory.meetings, 2)
        XCTAssertGreaterThanOrEqual(other.cat.memory.familiarity, simulation.cat.memory.familiarity)
    }
    func testTouchCreditsSurviveRepeatedLaunchesWithinSameMeeting() throws {
        var simulation = Simulation()
        for _ in 0..<4 {
            simulation.run(5)
            _ = simulation.cat.interact(.gentleTouch, in: simulation.context)
            simulation.run(3)
            let saved = try XCTUnwrap(simulation.cat.persistentState)
            var next = Simulation()
            try next.cat.restorePersistentState(saved)
            simulation = next
        }
        XCTAssertEqual(simulation.cat.memory.effectiveTouches, 3)
    }
    func testRepeatedGreetingsRespectMeowCooldown() {
        var simulation = Simulation()
        simulation.run(5)
        var calls = 0
        for _ in 0..<5 {
            _ = simulation.cat.interact(.greet, in: simulation.context)
            for _ in 0..<80 {
                calls += simulation.step().sounds.filter { $0 == PaperCatSounds.greeting }.count
            }
        }
        XCTAssertEqual(calls, 1)
    }
    func testQuietCompanionshipIsRememberedWithoutInventingTouchHistory() throws {
        var simulation = Simulation()
        simulation.run(125)
        XCTAssertTrue(simulation.cat.memory.prefersQuiet)
        let saved = try XCTUnwrap(simulation.cat.persistentState)
        var next = Simulation()
        try next.cat.restorePersistentState(saved)
        next.run(5)
        XCTAssertTrue(next.cat.interact(.greet, in: next.context))
        XCTAssertEqual(next.step().caption, L10n.text("可以不说话，一起晒会儿太阳。"))
        XCTAssertEqual(next.cat.memory.effectiveTouches, 0)
    }
    func testMeetingTimestampUsesEffectiveCompanionshipNotLaunchTime() throws {
        var simulation = Simulation()
        simulation.run(120, progress: 0)
        XCTAssertNil(simulation.cat.memory.lastMeeting)
        simulation.run(65)
        let date = try XCTUnwrap(simulation.cat.memory.lastMeeting)
        XCTAssertGreaterThanOrEqual(date.timeIntervalSince1970, 179.9)
        XCTAssertLessThan(date.timeIntervalSince1970, 186)
    }
    func testBriefFocusChangesDoNotCreateAnotherMeeting() {
        var simulation = Simulation()
        simulation.cat.sessionEnded(at: Date(timeIntervalSince1970: 0))
        simulation.cat.sessionBegan(at: Date(timeIntervalSince1970: 10000))
        simulation.run(65)
        for index in 0..<5 {
            simulation.cat.sessionEnded(at: Date(timeIntervalSince1970: 10065 + Double(index) * 70))
            simulation.cat.sessionBegan(at: Date(timeIntervalSince1970: 10070 + Double(index) * 70))
            simulation.run(65)
        }
        XCTAssertEqual(simulation.cat.memory.meetings, 1)
        simulation.cat.sessionEnded(at: Date(timeIntervalSince1970: 10400))
        simulation.cat.sessionBegan(at: Date(timeIntervalSince1970: 12400))
        simulation.run(65)
        XCTAssertEqual(simulation.cat.memory.meetings, 2)
    }
    func testFutureStateAndBrokenStateDoNotMutateMemory() throws {
        var cat = PaperCat()
        let original = cat.persistentState
        XCTAssertThrowsError(try cat.restorePersistentState(Data("{\"version\":2}".utf8))) { error in
            guard case StateRestoreError.unsupportedVersion(2) = error else { return XCTFail("应保护未来版本") }
        }
        XCTAssertEqual(cat.persistentState, original)
        XCTAssertThrowsError(try cat.restorePersistentState(Data("broken".utf8)))
        XCTAssertEqual(cat.persistentState, original)
    }
}
