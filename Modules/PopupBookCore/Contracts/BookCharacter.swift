import Foundation

public protocol BookCharacter {
    associatedtype Pose
    var id: CharacterID { get }
    var requiredAnchors: Set<AnchorID> { get }
    var pose: Pose { get }
    var accessibilityState: String { get }
    var persistentState: Data? { get }
    var interactionUnavailableMessage: String { get }
    mutating func restorePersistentState(_ data: Data) throws
    mutating func sessionBegan(at date: Date)
    mutating func sessionEnded(at date: Date?)
    mutating func advance(in context: WorldContext) -> CharacterOutput<Pose>
    @discardableResult mutating func interact(_ interaction: CharacterInteraction, in context: WorldContext)
        -> Bool
}

/// Optional persistence/lifecycle hooks keep basic and test actors lightweight.
extension BookCharacter {
    public var persistentState: Data? { nil }
    public var interactionUnavailableMessage: String { L10n.text("现在还不适合互动，稍等一下再试试。") }
    public mutating func restorePersistentState(_ data: Data) throws {}
    public mutating func sessionBegan(at date: Date) {}
    public mutating func sessionEnded(at date: Date?) {}
}
