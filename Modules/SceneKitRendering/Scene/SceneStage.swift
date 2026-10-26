import AppKit
import PopupBookCore
import SceneKit

@MainActor public final class SceneStage {
    public let scene: SCNScene
    public let camera: SCNNode
    public let anchors: [AnchorID: SCNNode]
    public init(scene: SCNScene, camera: SCNNode, anchors: [AnchorID: SCNNode]) {
        self.scene = scene
        self.camera = camera
        self.anchors = anchors
    }
    public func anchor(_ id: AnchorID) throws -> SCNNode {
        guard let n = anchors[id] else { throw BookConfigurationError.missingAnchors([id]) }
        return n
    }
}
