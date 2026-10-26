import AppKit
import PopupBookCore
import SceneKit

@MainActor public final class HitRegistry {
    private var identities: [ObjectIdentifier: CharacterID] = [:]
    public init() {}
    public func register(_ node: SCNNode, as id: CharacterID) { identities[ObjectIdentifier(node)] = id }
    public func unregister(_ node: SCNNode) { identities.removeValue(forKey: ObjectIdentifier(node)) }
    public func character(for node: SCNNode) -> CharacterID? {
        var current: SCNNode? = node
        while let n = current {
            if let id = identities[ObjectIdentifier(n)] { return id }
            current = n.parent
        }
        return nil
    }
}
