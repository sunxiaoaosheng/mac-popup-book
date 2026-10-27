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
    private let stateStore: (any StateStore)?
    private let wallClock: (any WallClock)?
    private var lastSavedState: Data?
    private var lastSaveTime = -5.0
    private var stateWritable = true
    private var persistenceNotice: String?
    private var desiredLoops: Set<SoundID> = []
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
        stateStore: (any StateStore)? = nil, wallClock: (any WallClock)? = nil,
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
        self.stateStore = stateStore
        self.wallClock = wallClock
        self.present = present
        self.soundEnabled = settings.soundEnabled
        self.caption = scene.guidance.initialCaption
        _ = fold.calibrate(settings.openAngle)
        restoreState()
    }
    public func setActive(_ value: Bool) {
        guard value != active else { return }
        if !value {
            character.sessionEnded(at: wallClock?.date)
            desiredLoops.removeAll()
            persist(force: true)
        } else if let wallClock {
            character.sessionBegan(at: wallClock.date)
        }
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
        if active && enabled { for sound in desiredLoops { audio.startLoop(sound) } }
        onChange?()
    }
    @discardableResult public func calibrate() -> Bool {
        noticeUntil = clock.now + 3
        guard let angle = fold.angle, fold.calibrate(angle) else {
            notice = L10n.text("请先把屏幕打开至 80°～120°，再校准。")
            onChange?()
            return false
        }
        settings.openAngle = fold.openAngle
        notice = L10n.text("已将 %@° 设为展开位置。", String(Int(fold.openAngle)))
        onChange?()
        return true
    }
    @discardableResult public func interact(with id: CharacterID, interaction: CharacterInteraction) -> Bool {
        guard active, id == character.id else { return false }
        let accepted = character.interact(interaction, in: context)
        if accepted {
            var immediate = context
            immediate.deltaTime = 0
            consume(character.advance(in: immediate), in: immediate)
            noticeUntil = 0
            updateNotice(at: clock.now)
            onChange?()
        } else {
            switch interaction {
            case .greet, .gentleTouch, .invite, .contactBegan:
                notice = character.interactionUnavailableMessage
                noticeUntil = clock.now + 2
                onChange?()
            default: break
            }
        }
        return accepted
    }
    public func stop() {
        character.sessionEnded(at: wallClock?.date)
        desiredLoops.removeAll()
        persist(force: true)
        active = false
        frameGeneration += 1
        generation += 1
        source.stop()
        clock.stop()
        audio.setActive(false)
        onChange?()
    }
    private func restoreState() {
        guard let stateStore else { return }
        do {
            if let data = try stateStore.load() {
                do {
                    try character.restorePersistentState(data)
                    lastSavedState = data
                    return
                } catch let error as StateRestoreError {
                    if case .unsupportedVersion = error {
                        stateWritable = false
                        persistenceNotice = error.localizedDescription
                        return
                    }
                } catch {
                    // Try only the previous validated snapshot below.
                }
            }
            if let backup = try stateStore.loadBackup() {
                try character.restorePersistentState(backup)
                lastSavedState = backup
                persistenceNotice = L10n.text("已从备份恢复相处记忆，原存档将在下次有效保存时替换。")
            } else if try stateStore.load() != nil {
                stateWritable = false
                persistenceNotice = L10n.text("相处记忆暂时无法读取，原文件已保留。本次仍可相处。")
            }
        } catch {
            stateWritable = false
            persistenceNotice = L10n.text("相处记忆暂时无法读取，原文件已保留：") + error.localizedDescription
        }
    }
    private func persist(force: Bool) {
        guard stateWritable, let stateStore, force || context.clock - lastSaveTime >= 5 else { return }
        lastSaveTime = context.clock
        guard let data = character.persistentState, data != lastSavedState else { return }
        do {
            try stateStore.save(data, previous: lastSavedState)
            lastSavedState = data
            persistenceNotice = nil
        } catch {
            persistenceNotice = L10n.text("这次相处还没有保存：") + error.localizedDescription
        }
    }
    private func configureInput() {
        generation += 1
        let expected = generation
        source.stop()
        if followsLid && active {
            notice = L10n.text("正在读取屏幕角度…")
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
        context.wallDate = wallClock?.date
        lastFrame = time
        let output = character.advance(in: context)
        consume(output, in: context)
        if soundEnabled, context.deltaTime > 0,
            abs(context.progress - previous) / context.deltaTime > 0.08,
            context.clock - lastMovementSound > 0.65
        {
            if let sound = scene.movementSound { audio.play(sound) }
            lastMovementSound = context.clock
        }
        persist(force: false)
        updateNotice(at: time)
        onChange?()
    }
    private func updateNotice(at time: TimeInterval) {
        if noticeUntil == 0 || time > noticeUntil {
            if followsLid {
                notice =
                    fold.sensorAvailable ? scene.guidance.following : L10n.text("角度暂不可用，画面已保留。可关闭跟随，使用手动预览。")
            } else {
                notice = scene.guidance.manual
            }
        }
        if let message = persistenceNotice { notice = message }
        if let error = audio.lastError { notice = error }
    }
    private func consume(_ output: CharacterOutput<Character.Pose>, in frame: WorldContext) {
        scene.update(in: frame, events: output.events)
        present(output.pose, frame)
        for command in output.soundCommands {
            switch command {
            case .beginLoop(let sound):
                desiredLoops.insert(sound)
                if soundEnabled { audio.startLoop(sound) }
            case .endLoop(let sound, let fade):
                desiredLoops.remove(sound)
                if soundEnabled { audio.stopLoop(sound, fade: fade) }
            }
        }
        if soundEnabled { for sound in output.sounds { audio.play(sound) } }
        caption = frame.progress < 0.12 ? scene.guidance.closedCaption : output.caption
    }
}
