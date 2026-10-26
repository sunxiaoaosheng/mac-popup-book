import Foundation

public protocol BookCharacter {
    associatedtype Pose
    var id: CharacterID { get }
    var requiredAnchors: Set<AnchorID> { get }
    var pose: Pose { get }
    var accessibilityState: String { get }
    mutating func advance(in context: WorldContext) -> CharacterOutput<Pose>
    @discardableResult mutating func interact(_ interaction: CharacterInteraction, in context: WorldContext)
        -> Bool
}
