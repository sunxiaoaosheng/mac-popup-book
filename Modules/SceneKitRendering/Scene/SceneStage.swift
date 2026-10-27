import AppKit
import PopupBookCore
import SceneKit

@MainActor public final class SceneStage {
    public let scene: SCNScene
    public let camera: SCNNode
    public let anchors: [AnchorID: SCNNode]
    private let contactSurfaces: [ContactSurface]
    private let framingPoints: [SCNVector3]
    public init(
        scene: SCNScene, camera: SCNNode, anchors: [AnchorID: SCNNode],
        contactSurfaces: [ContactSurface] = [],
        framingPoints: [SCNVector3] = []
    ) {
        self.scene = scene
        self.camera = camera
        self.anchors = anchors
        self.contactSurfaces = contactSurfaces
        self.framingPoints = framingPoints
    }
    public func anchor(_ id: AnchorID) throws -> SCNNode {
        guard let n = anchors[id] else { throw BookConfigurationError.missingAnchors([id]) }
        return n
    }
    public func fit(viewport: CGSize) {
        SceneFraming.fit(framingPoints, camera: camera, viewport: viewport)
    }
    /// Only explicitly supplied world surfaces participate; characters never become terrain.
    public func contactPoint(below position: SCNVector3) -> SCNVector3? {
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite else { return nil }
        let above = SCNVector3(position.x, position.y + 0.2, position.z)
        let below = SCNVector3(position.x, position.y - 1, position.z)
        return contactSurfaces.compactMap { $0.intersection(from: above, to: below) }.max { $0.y < $1.y }
    }
}
