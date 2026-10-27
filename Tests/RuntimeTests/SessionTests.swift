import PopupBookCore
import PopupBookRuntime
import XCTest

// A non-animal actor proves the runtime knows nothing about a species or a CatPose.
private struct Visitor: BookCharacter {
    let id = CharacterID("visitor")
    let requiredAnchors: Set<AnchorID> = [.entry]
    var pose = 0
    var accessibilityState: String { "访客" }
    mutating func advance(in context: WorldContext) -> CharacterOutput<Int> {
        pose += 1
        return CharacterOutput(pose: pose, caption: "访客", events: [.outside])
    }
    mutating func interact(_ interaction: CharacterInteraction, in context: WorldContext) -> Bool {
        pose += 100
        return true
    }
}
@MainActor private final class Clock: FrameClock {
    var now = 0.0
    var callback: ((TimeInterval) -> Void)?
    func start(_ callback: @escaping @MainActor (TimeInterval) -> Void) { self.callback = callback }
    func stop() { callback = nil }
    func advance(_ seconds: Double) {
        for _ in 0..<Int(seconds * 120) {
            now += 1.0 / 120
            callback?(now)
        }
    }
}
@MainActor private final class Input: AngleSource {
    var callbacks: [(AngleSample) -> Void] = []
    var stopped = 0
    func start(_ callback: @escaping @MainActor (AngleSample) -> Void) { callbacks.append(callback) }
    func stop() { stopped += 1 }
}
@MainActor private final class Settings: SettingsStore {
    var openAngle = 105.0
    var soundEnabled = false
}
@MainActor private final class Audio: AudioOutput {
    var lastError: String?
    var active = false
    var played: [SoundID] = []
    func setActive(_ active: Bool) { self.active = active }
    func play(_ sound: SoundID) { played.append(sound) }
}
@MainActor private final class Scene: BookScene {
    var availableAnchors: Set<AnchorID> = [.entry]
    let guidance = SceneGuidance(initialCaption: "欢迎", following: "跟随", manual: "手动", closedCaption: "收起")
    let movementSound: SoundID? = SoundID("fold")
    var updates = 0
    func update(in context: WorldContext, events: [CharacterEvent]) { updates += 1 }
}
@MainActor final class SessionTests: XCTestCase {
    func testAcceptedInteractionPresentsBeforeTheNextClockCallback() throws {
        let clock = Clock()
        var presentations: [Int] = []
        let session = try BookSession(
            character: Visitor(), scene: Scene(), source: Input(), clock: clock,
            settings: Settings(), audio: Audio()
        ) { pose, _ in presentations.append(pose) }
        session.setFollowing(false)
        session.setActive(true)
        XCTAssertTrue(session.interact(with: CharacterID("visitor"), interaction: .gentleTouch))
        XCTAssertEqual(presentations.last, 101)
        XCTAssertEqual(clock.now, 0)
        XCTAssertEqual(session.context.clock, 0)
        XCTAssertEqual(session.caption, "访客")
    }
    func testRepeatedInteractionsNeverPublishAnEmptyGuidanceRow() throws {
        let clock = Clock()
        let session = try BookSession(
            character: Visitor(), scene: Scene(), source: Input(), clock: clock,
            settings: Settings(), audio: Audio()
        ) { _, _ in }
        session.setFollowing(false)
        session.setActive(true)
        clock.advance(0.1)
        var notices: [String] = []
        session.onChange = { notices.append(session.notice) }
        for interaction in [
            CharacterInteraction.attention(ContactPoint(x: 0.5, y: 0.5)),
            .gentleTouch, .invite(.entry),
        ] {
            XCTAssertTrue(session.interact(with: CharacterID("visitor"), interaction: interaction))
            XCTAssertEqual(session.notice, "手动")
            clock.advance(0.1)
        }
        XCTAssertFalse(notices.isEmpty)
        XCTAssertTrue(notices.allSatisfy { $0 == "手动" })
    }
    func testAcceptedInteractionPreservesAudioErrorNotice() throws {
        let clock = Clock()
        let audio = Audio()
        let session = try BookSession(
            character: Visitor(), scene: Scene(), source: Input(), clock: clock,
            settings: Settings(), audio: audio
        ) { _, _ in }
        session.setFollowing(false)
        session.setActive(true)
        audio.lastError = "音频资源不可用"
        clock.advance(0.1)
        XCTAssertTrue(session.interact(with: CharacterID("visitor"), interaction: .gentleTouch))
        XCTAssertEqual(session.notice, "音频资源不可用")
    }
    func testManualReplacementPauseResumeAndNoHardware() throws {
        let input = Input()
        let clock = Clock()
        let scene = Scene()
        let audio = Audio()
        let settings = Settings()
        var presentations: [Int] = []
        let s = try BookSession(
            character: Visitor(), scene: scene, source: input, clock: clock, settings: settings, audio: audio
        ) { pose, _ in presentations.append(pose) }
        let controller: any BookSessionControl = s
        XCTAssertEqual(controller.characterID, CharacterID("visitor"))
        s.setFollowing(false)
        s.setManualProgress(0.5)
        s.setActive(true)
        clock.advance(1)
        XCTAssertTrue(input.callbacks.isEmpty)
        XCTAssertEqual(s.fold.progress, 0.5, accuracy: 0.001)
        XCTAssertFalse(presentations.isEmpty)
        XCTAssertTrue(s.interact(with: CharacterID("visitor"), interaction: .greet))
        XCTAssertFalse(s.interact(with: CharacterID("other"), interaction: .greet))
        s.setActive(false)
        let count = scene.updates
        let time = s.context.clock
        clock.advance(10)
        XCTAssertEqual(scene.updates, count)
        XCTAssertEqual(s.context.clock, time)
        XCTAssertFalse(audio.active)
        s.setActive(true)
        clock.advance(0.2)
        XCTAssertGreaterThan(s.context.clock, time)
        s.stop()
        XCTAssertNil(clock.callback)
    }
    func testStaleSensorCallbacksRecoveryAndSettings() throws {
        let input = Input()
        let clock = Clock()
        let scene = Scene()
        let audio = Audio()
        let settings = Settings()
        let s = try BookSession(
            character: Visitor(), scene: scene, source: input, clock: clock, settings: settings, audio: audio
        ) { _, _ in }
        s.setActive(true)
        input.callbacks[0](AngleSample(angle: 90, timestamp: clock.now))
        XCTAssertTrue(s.calibrate())
        XCTAssertEqual(settings.openAngle, 90)
        s.setSound(true)
        XCTAssertTrue(settings.soundEnabled)
        XCTAssertTrue(audio.active)
        s.setFollowing(false)
        s.setManualProgress(0.2)
        input.callbacks[0](AngleSample(angle: 110, timestamp: clock.now + 1))
        clock.advance(1)
        XCTAssertEqual(s.fold.progress, 0.2, accuracy: 0.001)
        s.setFollowing(true)
        clock.advance(1.3)
        XCTAssertFalse(s.fold.sensorAvailable)
        input.callbacks.last?(AngleSample(angle: 70, timestamp: clock.now))
        XCTAssertTrue(s.fold.sensorAvailable)
        s.setActive(false)
        input.callbacks.last?(AngleSample(angle: 120, timestamp: clock.now + 10))
        XCTAssertEqual(s.fold.angle, 70)
    }
    func testLateFrameAfterResumeIsIgnored() throws {
        let input = Input()
        let clock = Clock()
        let scene = Scene()
        let audio = Audio()
        let session = try BookSession(
            character: Visitor(), scene: scene, source: input, clock: clock, settings: Settings(),
            audio: audio
        ) { _, _ in }
        session.setFollowing(false)
        session.setActive(true)
        clock.advance(0.1)
        let expired = clock.callback
        session.setActive(false)
        session.setActive(true)
        let before = session.context.clock
        expired?(clock.now + 100)
        XCTAssertEqual(session.context.clock, before)
        clock.advance(0.1)
        XCTAssertGreaterThan(session.context.clock, before)
    }

    func testSceneOwnsClosedCaption() throws {
        let clock = Clock()
        let scene = Scene()
        let session = try BookSession(
            character: Visitor(), scene: scene, source: Input(), clock: clock, settings: Settings(),
            audio: Audio()
        ) { _, _ in }
        session.setFollowing(false)
        session.setManualProgress(0)
        session.setActive(true)
        clock.advance(1)
        XCTAssertEqual(session.caption, "收起")
    }

    func testMissingAnchorsFailsAtComposition() {
        let scene = Scene()
        scene.availableAnchors = []
        XCTAssertThrowsError(
            try BookSession(
                character: Visitor(), scene: scene, source: Input(), clock: Clock(), settings: Settings(),
                audio: Audio()
            ) { _, _ in })
    }
}
