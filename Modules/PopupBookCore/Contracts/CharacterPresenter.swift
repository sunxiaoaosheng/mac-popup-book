import Foundation

@MainActor public protocol CharacterPresenter: AnyObject {
    associatedtype Pose
    func update(_ pose: Pose, in context: WorldContext)
}
