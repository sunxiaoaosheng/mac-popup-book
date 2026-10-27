import AppKit
import SceneKit

/// An explicit planar contact patch, independent of lazily prepared render geometry.
@MainActor public struct ContactSurface {
    public enum Plane { case xy, xz }
    public enum Footprint { case rectangle, ellipse }
    public let node: SCNNode
    private let plane: Plane
    private let footprint: Footprint
    private let size: CGSize
    private let offset: CGFloat
    public init(node: SCNNode, plane: Plane, size: CGSize, offset: CGFloat, footprint: Footprint = .rectangle)
    {
        self.node = node
        self.plane = plane
        self.size = size
        self.offset = offset
        self.footprint = footprint
    }
    func intersection(from start: SCNVector3, to end: SCNVector3) -> SCNVector3? {
        var ancestor: SCNNode? = node
        while let current = ancestor {
            if current.isHidden { return nil }
            ancestor = current.parent
        }
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
            offset.isFinite
        else { return nil }
        let a = node.convertPosition(start, from: nil)
        let b = node.convertPosition(end, from: nil)
        let axisA = plane == .xy ? a.z : a.y
        let axisB = plane == .xy ? b.z : b.y
        guard abs(axisB - axisA) > 0.000001 else { return nil }
        let t = (offset - axisA) / (axisB - axisA)
        guard t.isFinite, (0...1).contains(t) else { return nil }
        let point = SCNVector3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t)
        let u = point.x / (size.width / 2)
        let v = (plane == .xy ? point.y : point.z) / (size.height / 2)
        let inside = footprint == .ellipse ? u * u + v * v <= 1 : abs(u) <= 1 && abs(v) <= 1
        guard inside else { return nil }
        return node.convertPosition(point, to: nil)
    }
}
