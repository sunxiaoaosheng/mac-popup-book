import AppKit
import PopupBookCore
import SceneKit

@MainActor public final class HitRegistry {
    private var identities: [ObjectIdentifier: (SCNNode, CharacterID)] = [:]
    public init() {}
    public var roots: [(SCNNode, CharacterID)] { Array(identities.values) }
    public func register(_ node: SCNNode, as id: CharacterID) {
        identities[ObjectIdentifier(node)] = (node, id)
    }
    public func unregister(_ node: SCNNode) { identities.removeValue(forKey: ObjectIdentifier(node)) }
    public func character(for node: SCNNode) -> CharacterID? { root(for: node)?.1 }
    public func root(for node: SCNNode) -> (SCNNode, CharacterID)? {
        var current: SCNNode? = node
        while let n = current {
            if let entry = identities[ObjectIdentifier(n)] { return entry }
            current = n.parent
        }
        return nil
    }
}
