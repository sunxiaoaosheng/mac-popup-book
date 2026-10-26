import Foundation
import PopupBookCore

public struct PaperCat: BookCharacter {
    public let id: CharacterID
    public let requiredAnchors: Set<AnchorID> = [.entry, .resting, .peek]
    public private(set) var pose = CatPose()
    private var previousEvent: CharacterEvent?
    private var context = WorldContext(progress: 1, clock: 0, deltaTime: 0, stableDuration: 0)
    public var accessibilityState: String { pose.mood.label }
    public init(id: CharacterID = CharacterID("resident")) { self.id = id }
    public mutating func interact(_ interaction: CharacterInteraction, in context: WorldContext) -> Bool {
        guard pose.mood == .resting, context.progress >= 0.85, pose.outside > 0.95 else { return false }
        pose.mood = .greeting
        pose.moodTime = 0
        return true
    }
    public mutating func advance(in context: WorldContext) -> CharacterOutput<CatPose> {
        self.context = context
        let dt = context.deltaTime
        pose.moodTime += dt
        var didMeow = false
        // Close has priority over every character action; fast folds compress the return.
        if context.progress < 0.75 && pose.mood != .sleeping && pose.mood != .waking
            && pose.mood != .returning
        {
            pose.mood = .returning
            pose.moodTime = 0
        }
        switch pose.mood {
        case .sleeping:
            pose.outside = 0
            if context.progress > 0.45 {
                pose.mood = .waking
                pose.moodTime = 0
            }
        case .waking:
            if context.progress < 0.35 {
                pose.mood = .sleeping
                pose.moodTime = 0
            } else if context.progress >= 0.85 && context.stableDuration >= 0.5 {
                pose.mood = .stretching
                pose.moodTime = 0
            }
        case .stretching:
            if pose.moodTime >= 1.1 {
                pose.mood = .walking
                pose.moodTime = 0
            }
        case .walking:
            pose.outside = min(1, pose.outside + dt / 1.8)
            if pose.outside >= 1 {
                pose.mood = .resting
                pose.moodTime = 0
            }
        case .resting: break
        case .greeting:
            if pose.moodTime - dt < 0.18 && pose.moodTime >= 0.18 { didMeow = true }
            if pose.moodTime >= 1.15 {
                pose.mood = .resting
                pose.moodTime = 0
            }
        case .returning:
            // Reverse smoothly from the current position, never reset to an endpoint.
            if context.progress > 0.85 && context.stableDuration >= 0.5 {
                pose.mood = .walking
                pose.moodTime = 0
            } else {
                let duration = max(0.16, 1.25 * smoothstep(0.3, 0.75, context.progress))
                pose.outside = max(0, pose.outside - dt / duration)
                if pose.outside <= 0 {
                    pose.mood = context.progress > 0.4 ? .waking : .sleeping
                    pose.moodTime = 0
                }
            }
        }
        pose.blink = pow(max(0, sin(context.clock * 0.67)), 48)

        let event: CharacterEvent
        switch pose.mood {
        case .sleeping, .waking: event = .restingInside
        case .stretching: event = .appearing
        case .walking, .resting, .greeting: event = .outside
        case .returning: event = .returningInside
        }
        let events = previousEvent == event ? [] : [event]
        previousEvent = event
        return CharacterOutput(
            pose: pose, caption: caption, events: events,
            sounds: didMeow ? [PaperCatSounds.greeting] : [])
    }
    private var caption: String {
        switch pose.mood {
        case .sleeping, .waking: return "嘘，窗边的小猫还在做梦。"
        case .stretching: return "伸个懒腰，今天也是好天气。"
        case .walking: return "门开了。有个小家伙想见你。"
        case .resting: return "阳光正好。点点小猫，和它打个招呼。"
        case .greeting: return "喵。很高兴你来了。"
        case .returning: return "再见之前，留一盏小灯。"
        }
    }
}
