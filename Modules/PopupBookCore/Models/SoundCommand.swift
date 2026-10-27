import Foundation

public enum SoundCommand: Equatable, Sendable {
    case beginLoop(SoundID)
    case endLoop(SoundID, fade: Double)
}
