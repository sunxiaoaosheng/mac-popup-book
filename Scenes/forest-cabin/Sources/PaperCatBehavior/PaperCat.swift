import Foundation
import PopupBookCore

public struct PaperCat: BookCharacter {
    public let id: CharacterID
    public let requiredAnchors: Set<AnchorID> = [.entry, .resting, .peek, .secondaryResting, .invitation]
    public private(set) var pose = CatPose()
    public private(set) var temperament = CatTemperament()
    public private(set) var memory = CatMemory()
    public var persistentState: Data? { memory.encoded() }
    private var activeWallDate: Date?
    private var activeLogicStart = 0.0
    private var memoryDate: Date? {
        let result =
            context.wallDate ?? activeWallDate?.addingTimeInterval(max(0, context.clock - activeLogicStart))
        guard let result, result.timeIntervalSince1970.isFinite else { return nil }
        return result
    }
    private var lastDeparture: Date?
    private var sessionSeconds = 0.0, meetingRecorded = false
    private var touchCredits = 0, touchRecorded = false, quietRecorded = false
    public mutating func restorePersistentState(_ data: Data) throws { memory = try CatMemory.decoded(data) }
    public mutating func sessionBegan(at date: Date) {
        guard date.timeIntervalSince1970.isFinite else {
            activeWallDate = nil
            return
        }
        if let lastDeparture, date.timeIntervalSince(lastDeparture) >= 1800 {
            sessionSeconds = 0
            meetingRecorded = false
            touchCredits = 0
            quietRecorded = false
        }
        activeWallDate = date
        activeLogicStart = context.clock
    }
    public mutating func sessionEnded(at date: Date?) {
        lastDeparture = date
        cancelContact()
    }
    private var rhythm: CatDailyRhythm
    private var previousEvent: CharacterEvent?
    private var context = WorldContext(progress: 1, clock: 0, deltaTime: 0, stableDuration: 0)
    private var contact = false, automaticTouchUntil = -1.0
    private var contactIntensity = 0.0, lastContactUpdate = -10.0, touchDuration = 0.0
    private var solitudeUntil = -1.0, actionDuration = 0.0, roamingTarget = 0.0
    private var lastAttention = -10.0, lastMeow = -20.0
    private var lastStepPhase: Int?
    private var excursionStretch = true
    private var purring = false
    private var acknowledgedAt = -100.0
    private var responseCaption: String?
    private var responseUntil = -1.0
    public var interactionUnavailableMessage: String {
        if pose.mood.isInside { return L10n.text("等它走到门前，再轻轻靠近。") }
        if context.clock < solitudeUntil { return L10n.text("它想自己整理一会儿，也愿意看看你。") }
        if pose.mood.isMoving { return L10n.text("等它站稳，再和它打招呼。") }
        return L10n.text("它已经看到你啦，轻轻等一会儿。")
    }
    public var accessibilityState: String { pose.mood.label }
    public init(id: CharacterID = CharacterID("resident"), random: any RandomSource = SeededRandom(seed: 42))
    {
        self.id = id
        rhythm = CatDailyRhythm(random: random)
    }
    private var canInteract: Bool {
        context.progress >= 0.85 && pose.outside > 0.95 && !pose.mood.isMoving
            && !pose.mood.isInside && pose.mood != .returning && pose.mood != .stretching
    }
    public mutating func interact(_ interaction: CharacterInteraction, in context: WorldContext) -> Bool {
        self.context = context
        if interaction == .contactEnded {
            cancelContact()
            return true
        }
        if case .invite(let anchor) = interaction, pose.mood == .strolling,
            context.progress >= 0.85, pose.outside > 0.95,
            [.invitation, .secondaryResting, .resting].contains(anchor)
        {
            acknowledge(L10n.text("来啦，正在往你这边走。"))
            return true
        }
        guard canInteract else { return false }
        switch interaction {
        case .greet:
            guard pose.mood != .greeting else { return false }
            responseCaption = nil
            temperament.notice()
            change(to: .greeting)
        case .attention(let point):
            guard context.clock - lastAttention >= 0.35 else { return false }
            if context.clock - lastAttention > 1.2 { acknowledge(nil) }
            lastAttention = context.clock
            pose.gaze = point
            temperament.notice()
        case .contactBegan(let point):
            guard context.clock >= solitudeUntil else {
                temperament.notice()
                return false
            }
            contact = true
            automaticTouchUntil = -1
            contactIntensity = 0
            lastContactUpdate = -10
            touchDuration = 0
            touchRecorded = false
            pose.gaze = point
            acknowledge(L10n.text("轻轻的，它已经感觉到了。"))
        case .contactMoved(let point, let intensity):
            guard contact, intensity.isFinite else { return false }
            pose.gaze = point
            contactIntensity = clamp(intensity)
            lastContactUpdate = context.clock
        case .gentleTouch:
            guard !contact, context.clock >= solitudeUntil, temperament.willingness >= 0.52 else {
                temperament.notice()
                return false
            }
            contact = true
            touchDuration = 0
            touchRecorded = false
            automaticTouchUntil = context.clock + 2
            contactIntensity = 0.5
            lastContactUpdate = context.clock
            change(to: .petting)
            acknowledge(L10n.text("它靠着你的手，慢慢放松下来。"))
        case .invite(let anchor):
            guard anchor == .invitation || anchor == .secondaryResting || anchor == .resting else {
                return false
            }
            cancelContact()
            if context.clock < solitudeUntil {
                change(to: .observing)
                actionDuration = 0.6
                acknowledge(L10n.text("它看到邀请了，想先歇一小会儿。"))
            } else {
                roamingTarget = anchor == .resting ? 0 : 1
                if abs(roamingTarget - pose.roaming) < 0.02 {
                    change(to: .observing)
                    actionDuration = 0.6
                    acknowledge(L10n.text("就在你身边啦。"))
                } else {
                    change(to: .strolling)
                    acknowledge(L10n.text("来啦，往你这边走。"))
                }
            }
        case .contactEnded: break
        }
        rhythm.postpone(after: context.clock)
        return true
    }
    public mutating func advance(in context: WorldContext) -> CharacterOutput<CatPose> {
        self.context = context
        let dt = context.deltaTime.isFinite ? clamp(context.deltaTime, 0, 0.1) : 0
        pose.moodTime += dt
        var sounds: [SoundID] = []
        if context.progress >= 0.85 {
            sessionSeconds += dt
            if sessionSeconds >= 60, !meetingRecorded, let memoryDate {
                _ = memory.recordMeeting(at: memoryDate)
                meetingRecorded = true
            }
            if sessionSeconds >= 120 && !quietRecorded && touchCredits == 0 {
                if let memoryDate { memory.recordQuiet(at: memoryDate) }
                quietRecorded = true
            }
        }
        if context.progress < 0.75 && !pose.mood.isInside && pose.mood != .returning {
            cancelContact()
            change(to: .returning)
        }
        if contact && automaticTouchUntil > 0 {
            if context.clock <= automaticTouchUntil + 0.000000001 {
                lastContactUpdate = context.clock
            } else {
                cancelContact()
            }
        }
        let touched =
            contact && context.clock - lastContactUpdate <= 0.18 && contactIntensity > 0
            && context.clock >= solitudeUntil && context.progress >= 0.85
        temperament.advance(dt, touched: touched)
        if !touched { touchDuration = 0 }
        if touched && !pose.mood.isMoving && !pose.mood.isInside && pose.mood != .returning {
            touchDuration += dt
            if touchDuration + 0.000000001 >= 2 && !touchRecorded && touchCredits < 3 {
                if let memoryDate, memory.recordTouch(at: memoryDate) { touchCredits += 1 }
                touchRecorded = true
            }
            if touchDuration >= 0.12 && pose.mood != .petting { change(to: .petting) }
            if touchDuration >= 8 {
                solitudeUntil = context.clock + 8
                cancelContact()
                change(to: .grooming)
                actionDuration = 3
            }
        } else if pose.mood == .petting {
            change(to: .resting)
            rhythm.postpone(after: context.clock)
        }
        switch pose.mood {
        case .sleeping:
            pose.outside = 0
            pose.roaming = 0
            if context.progress > 0.45 { change(to: .waking) }
        case .waking:
            if context.progress < 0.35 {
                change(to: .sleeping)
            } else if context.progress >= 0.85 && context.stableDuration >= 0.5 {
                excursionStretch = true
                change(to: .stretching)
            }
        case .stretching:
            if pose.moodTime >= 1.1 { change(to: excursionStretch ? .walking : .resting) }
        case .walking:
            pose.outside = min(1, pose.outside + dt / 1.8)
            pose.roaming = max(0, pose.roaming - dt / 2)
            if pose.outside >= 1 && pose.roaming <= 0.001 {
                change(to: .resting)
            }
        case .resting:
            if context.clock >= rhythm.nextAction {
                let choice = rhythm.choose(at: context.clock)
                excursionStretch = false
                actionDuration = choice.1
                if choice.0 == .strolling { roamingTarget = pose.roaming < 0.5 ? 1 : 0 }
                change(to: choice.0)
            } else if context.clock - rhythm.lastInvitation > (memory.prefersQuiet ? 120 : 60)
                && context.clock >= solitudeUntil
                && context.clock - lastAttention > 35 && pose.moodTime > 12
            {
                rhythm.invite(at: context.clock)
                change(to: .inviting)
                actionDuration = 3
            }
        case .greeting:
            if pose.moodTime - dt < 0.18 && pose.moodTime >= 0.18 && context.clock - lastMeow >= 20 {
                lastMeow = context.clock
                sounds.append(PaperCatSounds.greeting)
            }
            if pose.moodTime >= 1.15 { change(to: .resting) }
        case .returning:
            if context.progress > 0.85 && context.stableDuration >= 0.5 {
                change(to: .walking)
            } else {
                let duration = max(0.16, 1.25 * smoothstep(0.3, 0.75, context.progress))
                pose.outside = max(0, pose.outside - dt / duration)
                pose.roaming *= max(0, 1 - dt / duration)
                if pose.outside <= 0 { change(to: context.progress > 0.4 ? .waking : .sleeping) }
            }
        case .strolling:
            let direction = roamingTarget >= pose.roaming ? 1.0 : -1.0
            pose.roaming += direction * min(abs(roamingTarget - pose.roaming), dt / 2)
            if abs(pose.roaming - roamingTarget) < 0.001 { change(to: .resting) }
        case .observing, .grooming, .settling, .inviting:
            if pose.moodTime >= actionDuration { change(to: .resting) }
        case .petting: break
        }
        if pose.mood == .returning {
            pose.facing = .pi
        } else if pose.mood == .strolling {
            pose.facing = roamingTarget >= pose.roaming ? -0.25 : 0.25
        } else {
            pose.facing = 0
        }
        if pose.mood.isMoving {
            let phase = Int(context.clock * 12 / .pi)
            if lastStepPhase != phase {
                sounds.append(PaperCatSounds.footstep)
                lastStepPhase = phase
            }
        } else {
            lastStepPhase = nil
        }
        let targetTouch = pose.mood == .petting ? 1.0 : 0.0
        pose.touchBlend += (targetTouch - pose.touchBlend) * (1 - exp(-dt / 0.09))
        pose.acknowledgement = exp(-max(0, context.clock - acknowledgedAt) / 0.35)
        pose.relaxation = temperament.relaxation
        pose.attention = temperament.attention
        pose.earTilt = temperament.attention * (0.15 + sin(context.clock * 0.8) * 0.12)
        pose.tailEnergy = 0.5 - 0.3 * pose.touchBlend
        pose.blink = max(pow(max(0, sin(context.clock * 0.67)), 48), pose.touchBlend * 0.88)
        let event: CharacterEvent
        if pose.mood.isInside {
            event = .restingInside
        } else if pose.mood == .returning {
            event = .returningInside
        } else if pose.mood == .stretching && excursionStretch {
            event = .appearing
        } else {
            event = .outside
        }
        var soundCommands: [SoundCommand] = []
        let shouldPurr = pose.mood == .petting && touched && touchDuration >= 0.35
        if shouldPurr != purring {
            soundCommands.append(
                shouldPurr ? .beginLoop(PaperCatSounds.purr) : .endLoop(PaperCatSounds.purr, fade: 0.3))
            purring = shouldPurr
        }
        let events = previousEvent == event ? [] : [event]
        previousEvent = event
        return CharacterOutput(
            pose: pose, caption: caption, events: events, sounds: sounds, soundCommands: soundCommands)
    }
    private mutating func change(to mood: CatMood) {
        pose.mood = mood
        pose.moodTime = 0
        if mood == .resting { rhythm.postpone(after: context.clock) }
        if mood == .returning || mood.isInside { responseCaption = nil }
    }
    private mutating func acknowledge(_ caption: String?) {
        temperament.notice()
        acknowledgedAt = context.clock
        pose.acknowledgement = 1
        if let caption {
            responseCaption = caption
            responseUntil = context.clock + 1.2
        }
    }
    private mutating func cancelContact() {
        contact = false
        contactIntensity = 0
        automaticTouchUntil = -1
        if pose.mood == .petting { change(to: .resting) }
    }
    private var caption: String {
        if context.clock < responseUntil, let responseCaption { return responseCaption }
        switch pose.mood {
        case .sleeping, .waking: return L10n.text("嘘，窗边的小猫还在做梦。")
        case .stretching: return L10n.text("伸个懒腰，今天也是好天气。")
        case .walking: return L10n.text("门开了。有个小家伙想见你。")
        case .resting: return memory.prefersQuiet ? L10n.text("它在你身旁，安静坐着。") : L10n.text("你可以靠近一点，也可以一起晒太阳。")
        case .greeting:
            if memory.prefersQuiet { return L10n.text("可以不说话，一起晒会儿太阳。") }
            if memory.effectiveTouches > 0 { return L10n.text("喵。它还记得你轻轻靠近的样子。") }
            return memory.meetings > 0 ? L10n.text("你又来了，门前的位置还留着。") : L10n.text("喵。很高兴你来了。")
        case .returning: return L10n.text("再见之前，留一盏小灯。")
        case .observing: return L10n.text("它看了看树叶，又悄悄看看你。")
        case .grooming: return L10n.text("稍等一下，它想把毛毛理顺。")
        case .settling: return L10n.text("换个姿势，继续陪你。")
        case .strolling: return L10n.text("去那边坐坐，好吗？")
        case .petting: return L10n.text("嗯，这样轻轻的，刚刚好。")
        case .inviting: return L10n.text("它抬起爪子，想请你靠近一点。")
        }
    }
}
