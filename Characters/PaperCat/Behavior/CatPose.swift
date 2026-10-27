import Foundation
import PopupBookCore

public enum CatMood: String, CaseIterable, Sendable {
    case sleeping, waking, stretching, walking, resting, greeting, returning
    case observing, grooming, settling, strolling, petting, inviting
    public var label: String {
        switch self {
        case .sleeping: return L10n.text("睡觉")
        case .waking: return L10n.text("醒来")
        case .stretching: return L10n.text("伸懒腰")
        case .walking: return L10n.text("出门")
        case .resting: return L10n.text("晒太阳")
        case .greeting: return L10n.text("打招呼")
        case .returning: return L10n.text("回屋")
        case .observing: return L10n.text("好奇地看看")
        case .grooming: return L10n.text("整理毛发")
        case .settling: return L10n.text("换个舒服的姿势")
        case .strolling: return L10n.text("换个地方坐坐")
        case .petting: return L10n.text("享受轻抚")
        case .inviting: return L10n.text("邀请你靠近")
        }
    }
    public var isInside: Bool { self == .sleeping || self == .waking }
    public var isMoving: Bool { self == .walking || self == .returning || self == .strolling }
}

public struct CatPose {
    public var mood: CatMood = .sleeping
    public var outside = 0.0
    public var moodTime = 0.0
    public var blink = 0.0
    public var relaxation = 0.2
    public var attention = 0.0
    public var gaze = ContactPoint.center
    public var earTilt = 0.0
    public var tailEnergy = 0.5
    public var roaming = 0.0
    public var facing = 0.0
    public var touchBlend = 0.0
    public var acknowledgement = 0.0
    public init() {}
}

public enum PaperCatSounds {
    public static let greeting = SoundID("paper-cat.greeting")
    public static let purr = SoundID("paper-cat.purr")
    public static let footstep = SoundID("paper-cat.footstep")
}
