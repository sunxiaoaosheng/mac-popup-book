import Foundation
import PopupBookCore

/// Coordinates ports only. It has no knowledge of a renderer, species, or hardware API.
@MainActor public final class BookSession<Character: BookCharacter>: BookSessionControl {
    public var characterID: CharacterID { character.id }
    public var characterAccessibility: String { character.accessibilityState }
    public private(set) var fold = FoldState()
    public private(set) var character: Character
    public private(set) var context = WorldContext(progress: 1, clock: 0, deltaTime: 0, stableDuration: 0)
    public private(set) var active = false
    public private(set) var followsLid = true
    public private(set) var caption = ""
    public private(set) var notice = ""
    public private(set) var soundEnabled: Bool
    public var onChange: (() -> Void)?
    private let scene: any BookScene
    private let source: any AngleSource
    private let clock: any FrameClock
    private let settings: any SettingsStore
    private let audio: any AudioOutput
    private let present: (Character.Pose, WorldContext) -> Void
    private var generation = 0
    private var frameGeneration = 0
    private var manual = 1.0
    private var lastFrame = 0.0
    private var lastReading = 0.0
    private var lastMovementSound = -10.0
    private var noticeUntil = 0.0
    public init(
        character: Character, scene: any BookScene, source: any AngleSource, clock: any FrameClock,
        settings: any SettingsStore, audio: any AudioOutput,
        present: @escaping (Character.Pose, WorldContext) -> Void
    ) throws {
        let missing = character.requiredAnchors.subtracting(scene.availableAnchors)
        guard missing.isEmpty else { throw BookConfigurationError.missingAnchors(missing) }
        self.character = character
        self.scene = scene
        self.source = source
        self.clock = clock
        self.settings = settings
        self.audio = audio
        self.present = present
        self.soundEnabled = settings.soundEnabled
        self.caption = scene.guidance.initialCaption
        _ = fold.calibrate(settings.openAngle)
    }
    public func setActive(_ value: Bool) {
        guard value != active else { return }
        active = value
        frameGeneration += 1
        let frameToken = frameGeneration
        clock.stop()
        configureInput()
        audio.setActive(active && soundEnabled)
        if active {
            lastFrame = clock.now
            lastReading = clock.now
            clock.start { [weak self] time in
                guard let self, self.frameGeneration == frameToken else { return }
                self.tick(at: time)
            }
        }
        onChange?()
    }
    public func setFollowing(_ follow: Bool) {
        followsLid = follow
        configureInput()
        onChange?()
    }
    public func setManualProgress(_ p: Double) {
        guard p.isFinite else { return }
        manual = clamp(p)
        if !followsLid { fold.target = manual }
    }
    public func setSound(_ enabled: Bool) {
        soundEnabled = enabled
        settings.soundEnabled = enabled
        audio.setActive(active && enabled)
        onChange?()
    }
    @discardableResult public func calibrate() -> Bool {
        noticeUntil = clock.now + 3
        guard let angle = fold.angle, fold.calibrate(angle) else {
            notice = "请先把屏幕打开至 80°～120°，再校准。"
            onChange?()
            return false
        }
        settings.openAngle = fold.openAngle
        notice = "已将 \(Int(fold.openAngle))° 设为展开位置。"
        onChange?()
        return true
    }
    @discardableResult public func interact(with id: CharacterID, interaction: CharacterInteraction) -> Bool {
        guard active, id == character.id else { return false }
        return character.interact(interaction, in: context)
    }
    public func stop() {
        active = false
        frameGeneration += 1
        generation += 1
        source.stop()
        clock.stop()
        audio.setActive(false)
        onChange?()
    }
    private func configureInput() {
        generation += 1
        let expected = generation
        source.stop()
        if followsLid && active {
            notice = "正在读取屏幕角度…"
            lastReading = clock.now
            source.start { [weak self] sample in
                guard let self, self.generation == expected, self.active, self.followsLid else { return }
                self.lastReading = self.clock.now
                self.fold.receive(sample)
            }
        } else if !followsLid {
            fold.target = manual
            notice = scene.guidance.manual
        }
    }
    private func tick(at time: Double) {
        guard active, time.isFinite, time >= lastFrame else { return }
        if followsLid && time - lastReading > 1 {
            fold.receive(AngleSample(angle: nil, timestamp: lastReading))
            fold.receive(AngleSample(angle: nil, timestamp: time))
        }
        let previous = fold.progress
        context = fold.advance(time - lastFrame)
        lastFrame = time
        let output = character.advance(in: context)
        scene.update(in: context, events: output.events)
        present(output.pose, context)
        if soundEnabled {
            if context.deltaTime > 0, abs(context.progress - previous) / context.deltaTime > 0.08,
                context.clock - lastMovementSound > 0.65
            {
                if let sound = scene.movementSound { audio.play(sound) }
                lastMovementSound = context.clock
            }
            for sound in output.sounds { audio.play(sound) }
        }
        caption = context.progress < 0.12 ? scene.guidance.closedCaption : output.caption
        if followsLid && time > noticeUntil {
            notice = fold.sensorAvailable ? scene.guidance.following : "角度暂不可用，画面已保留。可关闭跟随，使用手动预览。"
        }
        if let error = audio.lastError { notice = error }
        onChange?()
    }
}
