import Foundation

@MainActor public protocol BookScene: AnyObject {
    var guidance: SceneGuidance { get }
    var availableAnchors: Set<AnchorID> { get }
    var movementSound: SoundID? { get }
    func update(in context: WorldContext, events: [CharacterEvent])
}
