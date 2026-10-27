import Foundation
import PopupBookCore

/// The only writer of book navigation and process state. It never imports a renderer or a page.
@MainActor public final class BookCoordinator {
    public let registry: PageRegistry
    public private(set) var state = BookState()
    public private(set) var fold = FoldState()
    public private(set) var following = true
    public private(set) var soundEnabled: Bool
    public var initialPage: String?
    public var onChange: (() -> Void)?
    public var onPageSelected: ((String) -> Void)?
    public var onSounds: ((String, [PageSound]) -> Void)?
    public var onScopeEnded: ((String) -> Void)?
    public var onScopeActive: ((String, Bool) -> Void)?
    private let source: any AngleSource
    private let clock: any FrameClock
    private let settings: any SettingsStore
    private let wallClock: (any WallClock)?
    private let factory: (PageDescriptor) -> any PageProcessPort
    private var ports: [String: any PageProcessPort] = [:]
    private var epochs: [String: Int] = [:]
    private var started: [String: Double] = [:]
    private var lastFrames: [String: Double] = [:]
    private var lastTick = 0.0
    private var phaseTime = 0.0
    private var context = WorldContext(progress: 1, clock: 0, deltaTime: 0, stableDuration: 0)
    private var manual = 1.0
    private var inputGeneration = 0
    private var lastReading = 0.0
    private var inputTimestamp = 0.0
    public init(
        registry: PageRegistry, source: any AngleSource, clock: any FrameClock, settings: any SettingsStore,
        wallClock: (any WallClock)? = nil, factory: @escaping (PageDescriptor) -> any PageProcessPort
    ) {
        self.registry = registry
        self.source = source
        self.clock = clock
        self.settings = settings
        self.wallClock = wallClock
        self.factory = factory
        soundEnabled = settings.soundEnabled
        _ = fold.calibrate(settings.openAngle)
    }
    public func setActive(_ value: Bool) {
        guard value != state.active else { return }
        state.active = value
        if value {
            lastTick = clock.now
            for id in started.keys {
                started[id] = clock.now
                lastFrames[id] = clock.now
            }
            if let id = state.current, state.phase == .idle, !isFailed(id) {
                onScopeActive?(id, soundEnabled)
            }
            configureInput()
            clock.start { [weak self] time in self?.tick(time) }
            if state.current == nil, let first = registry.pages.first {
                open(
                    initialPage.flatMap { id in registry.pages.contains(where: { $0.id == id }) ? id : nil }
                        ?? first.id)
            }
        } else {
            inputGeneration += 1
            source.stop()
            clock.stop()
            for (id, port) in ports {
                port.pause()
                if state.pageStates[id] == .running || state.pageStates[id] == .ready {
                    state.pageStates[id] = .paused
                }
                onScopeActive?(id, false)
            }
        }
        onChange?()
    }
    public func setFollowing(_ value: Bool) {
        following = value
        configureInput()
        onChange?()
    }
    public func setManual(_ value: Double) {
        guard value.isFinite else { return }
        manual = clamp(value)
        if !following { fold.target = manual }
        onChange?()
    }
    public func setSound(_ value: Bool) {
        soundEnabled = value
        settings.soundEnabled = value
        if let id = state.current { onScopeActive?(id, value && state.active && state.phase == .idle) }
        onChange?()
    }
    @discardableResult public func calibrate() -> Bool {
        guard let angle = fold.angle, fold.calibrate(angle) else { return false }
        settings.openAngle = fold.openAngle
        onChange?()
        return true
    }
    public func open(_ id: String) {
        guard state.phase == .idle, let descriptor = registry.pages.first(where: { $0.id == id }) else {
            return
        }
        if state.current == id, case .failed = state.pageStates[id] {} else if state.current == id { return }
        state.target = id
        state.phase = .preparing
        phaseTime = 0
        epochs[id, default: 0] += 1
        let token = epochs[id]!
        ports[id]?.stop()
        let port = factory(descriptor)
        ports[id] = port
        state.pageStates[id] = .starting
        started[id] = clock.now
        port.onReady = { [weak self] in
            guard let self, self.epochs[id] == token, self.state.target == id else { return }
            self.state.pageStates[id] = .ready
            self.lastFrames[id] = self.clock.now
            if self.state.current == nil || self.state.current == id || self.isFailed(self.state.current) {
                self.select(id)
                self.state.phase = .expanding
            } else {
                self.state.phase = .collapsing
            }
            self.phaseTime = 0
            self.onChange?()
        }
        port.onFrame = { [weak self] output in
            guard let self, self.epochs[id] == token else { return }
            self.lastFrames[id] = self.clock.now
            if self.state.current == id {
                self.state.output = output
                self.state.pageStates[id] = self.state.active ? .running : .paused
                self.onSounds?(id, output.sounds)
                self.onChange?()
            }
        }
        port.onFailure = { [weak self] error in
            guard let self, self.epochs[id] == token else { return }
            self.fail(id, error)
        }
        port.start(epoch: token)
        onChange?()
    }
    public func move(_ offset: Int) {
        guard let current = state.current, let index = registry.pages.firstIndex(where: { $0.id == current })
        else { return }
        let n = index + offset
        if registry.pages.indices.contains(n) { open(registry.pages[n].id) }
    }
    public func handle(_ input: PageInput) {
        guard state.active, state.phase == .idle, let id = state.current, !isFailed(id) else { return }
        ports[id]?.handle(input)
    }
    public func stop() {
        setActive(false)
        for (id, port) in ports {
            port.terminate()
            onScopeEnded?(id)
        }
        ports = [:]
        started = [:]
        lastFrames = [:]
    }
    private func configureInput() {
        inputGeneration += 1
        let token = inputGeneration
        source.stop()
        guard state.active else { return }
        if following {
            lastReading = clock.now
            source.start { [weak self] sample in
                guard let self, self.inputGeneration == token, self.state.active, self.following else {
                    return
                }
                self.lastReading = self.clock.now
                self.inputTimestamp = sample.timestamp
                self.fold.receive(sample)
            }
        } else {
            fold.target = manual
        }
    }
    private func select(_ id: String) {
        state.current = id
        lastFrames[id] = clock.now
        onPageSelected?(id)
        onScopeActive?(id, soundEnabled && state.active && state.phase == .idle)
    }
    private func isFailed(_ id: String?) -> Bool {
        guard let id else { return true }
        if case .failed = state.pageStates[id] { return true }
        return false
    }
    private func fail(_ id: String, _ error: PageError) {
        epochs[id, default: 0] += 1
        ports[id]?.terminate()
        ports[id] = nil
        state.pageStates[id] = .failed(error)
        onScopeActive?(id, false)
        onScopeEnded?(id)
        started[id] = nil
        lastFrames[id] = nil
        if state.target == id {
            if state.phase != .preparing || state.current == nil || state.current == id { select(id) }
            state.target = nil
            state.phase = .idle
            phaseTime = 0
        }
        onChange?()
    }
    private func tick(_ time: Double) {
        guard state.active, time.isFinite else { return }
        let dt = clamp(time - lastTick, 0, 0.05)
        lastTick = time
        if following, time - lastReading > 1 {
            fold.receive(AngleSample(angle: nil, timestamp: inputTimestamp + time - lastReading))
        }
        context = fold.advance(dt)
        context.wallDate = wallClock?.date
        state.progress = context.progress
        for (id, _) in ports {
            if state.pageStates[id] == .starting, time - (started[id] ?? time) > 10 {
                fail(id, .startupTimeout)
                break
            }
            if id == state.current, !isFailed(id), state.pageStates[id] != .starting,
                time - (lastFrames[id] ?? time) > 3
            {
                fail(id, .stalled)
                break
            }
        }
        if context.progress >= 0.12 {
            switch state.phase {
            case .collapsing:
                phaseTime += dt
                if phaseTime >= 0.25 {
                    if let old = state.current {
                        onScopeActive?(old, false)
                        ports[old]?.stop()
                        ports[old] = nil
                        epochs[old, default: 0] += 1
                        onScopeEnded?(old)
                        state.pageStates[old] = .stopped
                        started[old] = nil
                        lastFrames[old] = nil
                    }
                    state.phase = .turning
                    phaseTime = 0
                }
            case .turning:
                phaseTime += dt
                state.turnProgress = min(1, phaseTime / 0.45)
                if phaseTime >= 0.45, let target = state.target {
                    select(target)
                    state.phase = .expanding
                    phaseTime = 0
                }
            case .expanding:
                phaseTime += dt
                if phaseTime >= 0.3 {
                    state.phase = .idle
                    state.target = nil
                    state.turnProgress = 0
                    if let id = state.current { onScopeActive?(id, soundEnabled) }
                }
            default: break
            }
        }
        if let id = state.current, !isFailed(id), state.phase != .turning {
            var frame = context
            if state.phase == .collapsing {
                frame.progress = context.progress * (1 - clamp(phaseTime / 0.25))
            }
            if state.phase == .expanding { frame.progress = context.progress * clamp(phaseTime / 0.3) }
            ports[id]?.advance(frame)
        }
        onChange?()
    }
}
