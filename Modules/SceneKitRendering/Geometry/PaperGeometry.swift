import AppKit
import SceneKit

extension NSColor {
    public convenience init(hex: Int) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}
/// Shared contour construction; no scene or character content lives here.
@MainActor public final class PaperGeometry {
    private var materials: [Int: SCNMaterial] = [:]
    public init() {}
    public func material(_ hex: Int) -> SCNMaterial {
        if let m = materials[hex] { return m }
        let m = SCNMaterial()
        m.diffuse.contents = NSColor(hex: hex)
        m.roughness.contents = 0.95
        m.lightingModel = .physicallyBased
        m.isDoubleSided = true
        materials[hex] = m
        return m
    }
    @discardableResult public func cut(
        _ path: NSBezierPath, _ color: Int, _ parent: SCNNode, x: Double = 0, y: Double = 0, z: Double = 0,
        thickness: Double = 0.025
    ) -> SCNNode {
        path.flatness = 0.015
        let g = SCNShape(path: path, extrusionDepth: thickness)
        g.chamferRadius = 0.007
        g.materials = [material(color)]
        let n = SCNNode(geometry: g)
        n.position = SCNVector3(x, y, z)
        n.castsShadow = true
        parent.addChildNode(n)
        return n
    }
    public func polygon(_ points: [(Double, Double)]) -> NSBezierPath {
        let p = NSBezierPath()
        guard let first = points.first else { return p }
        p.move(to: NSPoint(x: first.0, y: first.1))
        for pt in points.dropFirst() { p.line(to: NSPoint(x: pt.0, y: pt.1)) }
        p.close()
        return p
    }
    public func ellipse(_ w: Double, _ h: Double) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: -w / 2, y: -h / 2, width: w, height: h))
    }
    public func rounded(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) -> NSBezierPath {
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
    }
}
