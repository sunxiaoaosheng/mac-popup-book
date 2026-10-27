import Foundation
import SceneKit

/// Smooth grounding shared by volumetric presenters; no character or behavior state.
@MainActor public struct SurfacePlacement {
    public private(set) var height: CGFloat?
    public init() {}
    public mutating func update(at position: SCNVector3, in stage: SceneStage, deltaTime: Double) -> CGFloat {
        if let contact = stage.contactPoint(below: position) {
            let previous = height ?? contact.y
            let dt = deltaTime.isFinite ? min(0.1, max(0, deltaTime)) : 0
            height = previous + (contact.y - previous) * (1 - exp(-dt / 0.08))
        }
        // Preserve the previous height across a narrow seam, rather than jumping to an anchor.
        return height ?? position.y
    }
}
