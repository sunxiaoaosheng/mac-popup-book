import Foundation

/// A point inside a character's local interaction bounds, independent of a renderer.
public struct ContactPoint: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public init(x: Double, y: Double) {
        self.x = x.isFinite ? clamp(x) : 0.5
        self.y = y.isFinite ? clamp(y) : 0.5
    }
    public static let center = Self(x: 0.5, y: 0.5)
}

public enum CharacterInteraction: Equatable, Sendable {
    case greet
    case attention(ContactPoint)
    case contactBegan(ContactPoint)
    case contactMoved(ContactPoint, intensity: Double)
    case contactEnded
    case gentleTouch
    case invite(AnchorID)
}
