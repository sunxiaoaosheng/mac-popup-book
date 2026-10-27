import Foundation
import PopupBookCore
import PopupBookRuntime
import XCTest

@MainActor private final class TestDisplay: FrameClock {
    var now = 0.0
    var callback: ((Double) -> Void)?
    func start(_ onFrame: @escaping @MainActor (Double) -> Void) { callback = onFrame }
    func stop() { callback = nil }
    func step(_ duration: Double) {
        for _ in 0..<Int(duration * 60) {
            now += 1.0 / 60
            callback?(now)
        }
    }
}
@MainActor private final class TestAngle: AngleSource {
    var callbacks: [(AngleSample) -> Void] = []
    var stops = 0
    func start(_ callback: @escaping @MainActor (AngleSample) -> Void) { callbacks.append(callback) }
    func stop() { stops += 1 }
}
@MainActor private final class TestPreferences: SettingsStore {
    var openAngle = 105.0
    var soundEnabled = false
}
@MainActor private final class TestPort: PageProcessPort {
    var onReady: (() -> Void)?
    var onFrame: ((PagePresentation) -> Void)?
    var onFailure: ((PageError) -> Void)?
    var epoch = 0
    var stopped = false
    var paused = false
    var automaticFrames = true
    var inputs = 0
    var contexts: [WorldContext] = []
    func start(epoch: Int) { self.epoch = epoch }
    func advance(_ context: WorldContext) {
        contexts.append(context)
        if automaticFrames { onFrame?(PagePresentation(caption: "ready")) }
    }
    func handle(_ input: PageInput) { inputs += 1 }
    func pause() { paused = true }
    func stop() { stopped = true }
}
private func descriptor(_ id: String, version: Int = 1) -> Data {
    try! JSONSerialization.data(withJSONObject: [
        "id": id, "order": 0, "names": ["en": id, "zh-Hans": id], "contractVersion": version,
        "service": "local.test.\(id)", "product": "Worker", "audio": [],
    ])
}
@MainActor final class BookCoordinatorTests: XCTestCase {
    func testRegistryQuarantinesBadAndDuplicateEntries() {
        let registry = PageRegistry(
            descriptors: [
                descriptor("good"), descriptor("duplicate"), descriptor("duplicate"),
                descriptor("wrong", version: 9), Data("broken".utf8),
            ], published: ["good", "duplicate", "wrong", "missing"])
        XCTAssertEqual(registry.pages.map(\.id), ["good"])
        XCTAssertNotNil(registry.errors["duplicate"])
        XCTAssertNotNil(registry.errors["missing"])
    }
    func testNoPageStillAllowsShellToRun() {
        let clock = TestDisplay()
        let coordinator = BookCoordinator(
            registry: PageRegistry(descriptors: [], published: []), source: TestAngle(), clock: clock,
            settings: TestPreferences()
        ) { _ in TestPort() }
        coordinator.setFollowing(false)
        coordinator.setActive(true)
        clock.step(1)
        XCTAssertNil(coordinator.state.current)
        XCTAssertTrue(coordinator.state.active)
    }
    func testTransitionLifecycleAndOnlyTwoActivePorts() {
        let clock = TestDisplay()
        let input = TestAngle()
        var made: [String: TestPort] = [:]
        let coordinator = BookCoordinator(
            registry: PageRegistry(
                descriptors: [descriptor("red"), descriptor("blue")], published: ["red", "blue"]),
            source: input, clock: clock, settings: TestPreferences()
        ) { page in
            let port = TestPort()
            made[page.id] = port
            return port
        }
        coordinator.setFollowing(false)
        coordinator.setActive(true)
        let red = made["red"]!
        red.onReady?()
        clock.step(0.5)
        XCTAssertEqual(coordinator.state.current, "red")
        XCTAssertEqual(coordinator.state.phase, .idle)
        coordinator.handle(.action("tap"))
        XCTAssertEqual(red.inputs, 1)
        coordinator.open("blue")
        let blue = made["blue"]!
        coordinator.open("red")
        XCTAssertEqual(coordinator.state.target, "blue")
        blue.onReady?()
        coordinator.handle(.action("tap"))
        XCTAssertEqual(red.inputs, 1)
        clock.step(1.2)
        XCTAssertEqual(coordinator.state.current, "blue")
        XCTAssertEqual(coordinator.state.phase, .idle)
        XCTAssertTrue(red.stopped)
        XCTAssertFalse(blue.stopped)
        XCTAssertTrue(input.callbacks.isEmpty)
        XCTAssertTrue(blue.contexts.allSatisfy { $0.wallDate == nil })
        coordinator.stop()
        XCTAssertTrue(blue.stopped)
        XCTAssertNil(clock.callback)
    }
    func testFailedTargetPreservesCurrentAndLateFramesAreIgnored() {
        let clock = TestDisplay()
        var ports: [String: TestPort] = [:]
        let c = BookCoordinator(
            registry: PageRegistry(
                descriptors: [descriptor("red"), descriptor("blue")], published: ["red", "blue"]),
            source: TestAngle(), clock: clock, settings: TestPreferences()
        ) { d in
            let p = TestPort()
            ports[d.id] = p
            return p
        }
        c.setFollowing(false)
        c.setActive(true)
        ports["red"]!.onReady?()
        clock.step(0.5)
        c.open("blue")
        let failed = ports["blue"]!
        let late = failed.onReady
        failed.onFailure?(.missingResources)
        XCTAssertEqual(c.state.current, "red")
        XCTAssertEqual(c.state.phase, .idle)
        XCTAssertTrue(failed.stopped)
        late?()
        XCTAssertEqual(c.state.current, "red")
        XCTAssertEqual(c.state.phase, .idle)
        let old = ports["red"]!
        let oldFrame = old.onFrame
        c.open("blue")
        ports["blue"]!.onReady?()
        clock.step(1.2)
        oldFrame?(PagePresentation(caption: "stale"))
        XCTAssertNotEqual(c.state.output.caption, "stale")
    }
    func testStartupTimeoutStallAndManualRetry() {
        let clock = TestDisplay()
        var ports: [TestPort] = []
        let c = BookCoordinator(
            registry: PageRegistry(descriptors: [descriptor("red")], published: ["red"]), source: TestAngle(),
            clock: clock, settings: TestPreferences()
        ) { _ in
            let p = TestPort()
            ports.append(p)
            return p
        }
        c.setFollowing(false)
        c.setActive(true)
        clock.step(10.2)
        XCTAssertEqual(c.state.pageStates["red"], .failed(.startupTimeout))
        XCTAssertEqual(ports.count, 1)
        c.open("red")
        ports.last!.onReady?()
        clock.step(0.5)
        ports.last!.automaticFrames = false
        clock.step(3.2)
        XCTAssertEqual(c.state.pageStates["red"], .failed(.stalled))
        XCTAssertEqual(ports.count, 2)
    }
    func testPausedTimeDoesNotTriggerFailureAndRejectsOldAngleSource() {
        let clock = TestDisplay()
        let angle = TestAngle()
        let port = TestPort()
        let c = BookCoordinator(
            registry: PageRegistry(descriptors: [descriptor("red")], published: ["red"]), source: angle,
            clock: clock, settings: TestPreferences()
        ) { _ in port }
        c.setActive(true)
        angle.callbacks[0](AngleSample(angle: 100, timestamp: clock.now))
        port.onReady?()
        clock.step(0.5)
        c.setActive(false)
        let before = c.state.progress
        clock.step(30)
        XCTAssertEqual(c.state.progress, before)
        c.setFollowing(false)
        c.setManual(0.5)
        c.setActive(true)
        angle.callbacks[0](AngleSample(angle: 120, timestamp: clock.now + 1))
        clock.step(0.5)
        XCTAssertEqual(c.state.progress, 0.5, accuracy: 0.001)
        XCTAssertFalse(port.stopped)
    }
    func testPhysicalClosingPausesPageTurnWithoutQueueing() {
        let clock = TestDisplay()
        var ports: [String: TestPort] = [:]
        let c = BookCoordinator(
            registry: PageRegistry(
                descriptors: [descriptor("red"), descriptor("blue")], published: ["red", "blue"]),
            source: TestAngle(), clock: clock, settings: TestPreferences()
        ) { d in
            let p = TestPort()
            ports[d.id] = p
            return p
        }
        c.setFollowing(false)
        c.setActive(true)
        ports["red"]!.onReady?()
        clock.step(0.5)
        c.setManual(0)
        clock.step(0.5)
        c.open("blue")
        ports["blue"]!.onReady?()
        clock.step(1)
        XCTAssertEqual(c.state.phase, .collapsing)
        c.setManual(1)
        clock.step(1.4)
        XCTAssertEqual(c.state.current, "blue")
        XCTAssertEqual(c.state.phase, .idle)
    }
}
