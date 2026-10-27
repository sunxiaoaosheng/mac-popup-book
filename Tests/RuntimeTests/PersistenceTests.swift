import Foundation
import PopupBookCore
import XCTest

@testable import PopupBookRuntime

private struct SavedVisitor: BookCharacter {
    let id = CharacterID("saved-visitor")
    let requiredAnchors: Set<AnchorID> = []
    var pose = 3
    var touching = false
    private var sounded = false
    var persistentState: Data? { Data([UInt8(pose)]) }
    var accessibilityState: String { "访客" }
    mutating func restorePersistentState(_ data: Data) throws {
        guard let value = data.first, data.count == 1 else { throw StateRestoreError.invalidState }
        if value == 255 { throw StateRestoreError.unsupportedVersion(10) }
        if value == 0 { throw StateRestoreError.invalidState }
        pose = Int(value)
    }
    mutating func sessionEnded(at date: Date?) { touching = false }
    mutating func interact(_ interaction: CharacterInteraction, in context: WorldContext) -> Bool {
        if interaction == .greet {
            touching = true
            pose += 1
        }
        return true
    }
    mutating func advance(in context: WorldContext) -> CharacterOutput<Int> {
        var commands: [SoundCommand] = []
        if touching != sounded {
            commands = touching ? [.beginLoop(SoundID("loop"))] : [.endLoop(SoundID("loop"), fade: 0.3)]
            sounded = touching
        }
        return CharacterOutput(pose: pose, caption: "访客", events: [], soundCommands: commands)
    }
}
@MainActor private final class TestStore: StateStore {
    var data: Data?, backup: Data?
    var writes = 0, shouldFail = false
    func load() throws -> Data? { data }
    func loadBackup() throws -> Data? { backup }
    func save(_ data: Data, previous: Data?) throws {
        if shouldFail { throw CocoaError(.fileWriteNoPermission) }
        writes += 1
        backup = previous
        self.data = data
    }
}
@MainActor private final class TestClock: FrameClock {
    var now = 0.0
    var callback: (@MainActor (TimeInterval) -> Void)?
    func start(_ callback: @escaping @MainActor (TimeInterval) -> Void) { self.callback = callback }
    func stop() { callback = nil }
    func step() {
        now += 1.0 / 60
        callback?(now)
    }
}
@MainActor private final class TestInput: AngleSource {
    func start(_ callback: @escaping @MainActor (AngleSample) -> Void) { XCTFail("手动模式不应读取硬件") }
    func stop() {}
}
@MainActor private final class TestSettings: SettingsStore {
    var openAngle = 105.0
    var soundEnabled = false
}
@MainActor private final class TestScene: BookScene {
    var availableAnchors: Set<AnchorID> { [] }
    var movementSound: SoundID? { nil }
    var guidance: SceneGuidance {
        SceneGuidance(initialCaption: "", following: "", manual: "", closedCaption: "")
    }
    func update(in context: WorldContext, events: [CharacterEvent]) {}
}
@MainActor private final class TestAudio: AudioOutput {
    var lastError: String?
    var starts = 0, stops = 0, active = false
    func setActive(_ active: Bool) { self.active = active }
    func play(_ sound: SoundID) {}
    func startLoop(_ sound: SoundID) { starts += 1 }
    func stopLoop(_ sound: SoundID, fade: Double) { stops += 1 }
}
@MainActor final class PersistenceTests: XCTestCase {
    private func make(_ store: TestStore, _ clock: TestClock, _ audio: TestAudio? = nil) throws
        -> BookSession<SavedVisitor>
    {
        let session = try BookSession(
            character: SavedVisitor(), scene: TestScene(), source: TestInput(), clock: clock,
            settings: TestSettings(), audio: audio ?? TestAudio(), stateStore: store
        ) { _, _ in }
        session.setFollowing(false)
        return session
    }
    func testFutureVersionProtectsPrimaryAndBackup() throws {
        let store = TestStore()
        let clock = TestClock()
        store.data = Data([255])
        store.backup = Data([4])
        let session = try make(store, clock)
        session.setActive(true)
        clock.step()
        _ = session.interact(with: session.characterID, interaction: .greet)
        session.stop()
        XCTAssertEqual(store.writes, 0)
        XCTAssertEqual(store.data, Data([255]))
        XCTAssertEqual(store.backup, Data([4]))
    }
    func testRecoveryBacksUpOnlyValidatedState() throws {
        let store = TestStore()
        let clock = TestClock()
        store.data = Data([0])
        store.backup = Data([4])
        let session = try make(store, clock)
        XCTAssertEqual(session.character.pose, 4)
        session.setActive(true)
        _ = session.interact(with: session.characterID, interaction: .greet)
        session.stop()
        XCTAssertEqual(store.data, Data([5]))
        XCTAssertEqual(store.backup, Data([4]))
    }
    func testFailedSaveIsVisibleAndCanRetry() throws {
        let store = TestStore()
        let clock = TestClock()
        store.shouldFail = true
        let session = try make(store, clock)
        session.setActive(true)
        clock.step()
        XCTAssertTrue(session.notice.hasPrefix(L10n.text("这次相处还没有保存：")))
        XCTAssertNil(store.data)
        store.shouldFail = false
        session.stop()
        XCTAssertEqual(store.data, Data([3]))
    }
    func testEndingWhileMutedDoesNotReplayOnEnable() throws {
        let store = TestStore()
        let clock = TestClock()
        let audio = TestAudio()
        let session = try make(store, clock, audio)
        session.setActive(true)
        _ = session.interact(with: session.characterID, interaction: .greet)
        clock.step()
        XCTAssertEqual(audio.starts, 0)
        session.setSound(true)
        XCTAssertEqual(audio.starts, 1)
        session.setSound(false)
        session.setActive(false)
        session.setActive(true)
        clock.step()
        session.setSound(true)
        XCTAssertEqual(audio.starts, 1)
    }
    func testLoopLifecycleDoesNotReplayACompletedContact() throws {
        let store = TestStore()
        let clock = TestClock()
        let audio = TestAudio()
        let session = try make(store, clock, audio)
        session.setActive(true)
        session.setSound(true)
        _ = session.interact(with: session.characterID, interaction: .greet)
        clock.step()
        clock.step()
        XCTAssertEqual(audio.starts, 1)
        session.setActive(false)
        XCTAssertFalse(session.character.touching)
        XCTAssertFalse(audio.active)
        session.setActive(true)
        clock.step()
        XCTAssertEqual(audio.starts, 1)
        XCTAssertEqual(audio.stops, 1)
    }
}
