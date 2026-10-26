import Foundation
import PopupBookCore

public enum CatMood: String {
    case sleeping, waking, stretching, walking, resting, greeting, returning
    public var label: String {
        switch self {
        case .sleeping: return "睡觉"
        case .waking: return "醒来"
        case .stretching: return "伸懒腰"
        case .walking: return "出门"
        case .resting: return "晒太阳"
        case .greeting: return "打招呼"
        case .returning: return "回屋"
        }
    }
}

public struct CatPose {
    public var mood: CatMood = .sleeping
    public var outside = 0.0
    public var moodTime = 0.0
    public var blink = 0.0
    public init() {}
}

public enum PaperCatSounds {
    public static let greeting = SoundID("paper-cat.greeting")
}
