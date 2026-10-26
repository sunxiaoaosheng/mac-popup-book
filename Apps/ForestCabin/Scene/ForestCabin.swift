import AppKit
import PopupBookCore
import SceneKit
import SceneKitRendering

@MainActor public final class ForestCabin: BookScene {
    private let paper = PaperGeometry()
    public let scene = SCNScene()
    public let camera = SCNNode()
    public var stage: SceneStage { SceneStage(scene: scene, camera: camera, anchors: anchorNodes) }
    private var anchorNodes: [AnchorID: SCNNode] = [:]
    public var availableAnchors: Set<AnchorID> { Set(anchorNodes.keys) }
    public let guidance = SceneGuidance(
        initialCaption: "打开一页，遇见一座森林。", following: "让屏幕带着森林展开；停下来，看看住在这里的小家伙。", manual: "拖动进度，让森林慢慢展开。",
        closedCaption: "把森林，轻轻收进口袋。")
    public let movementSound: SoundID? = SoundID("paper.fold")
    private var hinges: [(SCNNode, Double, Double)] = []
    private let house = SCNNode()
    private let peek = SCNNode()
    private let lamp = SCNNode()
    private var returning = false
    private var foliage: [SCNNode] = []
    private let cream = 0xF4E9CD
    public init() {
        build()
    }
    private func hinge(x: Double, z: Double, start: Double, end: Double) -> SCNNode {
        let n = SCNNode()
        n.position = SCNVector3(x, 0.13 + Double(hinges.count) * 0.003, z)
        scene.rootNode.addChildNode(n)
        hinges.append((n, start, end))
        return n
    }
    private func box(_ w: Double, _ h: Double, _ l: Double, color: Int, at p: SCNVector3) -> SCNNode {
        let g = SCNBox(width: w, height: h, length: l, chamferRadius: 0.045)
        g.materials = [paper.material(color)]
        let n = SCNNode(geometry: g)
        n.position = p
        scene.rootNode.addChildNode(n)
        return n
    }
    private func build() {
        scene.background.contents = NSColor(hex: 0xE9E3D7)
        scene.lightingEnvironment.intensity = 0.6
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 6.5
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = 100
        camera.camera?.wantsHDR = false
        camera.position = SCNVector3(5.6, 8.8, 16.5)
        camera.look(at: SCNVector3(0, 0.7, 0))
        scene.rootNode.addChildNode(camera)
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 1550
        sun.light?.temperature = 5100
        sun.light?.castsShadow = true
        sun.light?.shadowMode = .deferred
        sun.light?.shadowRadius = 5
        sun.light?.shadowSampleCount = 16
        sun.light?.shadowColor = NSColor(hex: 0x645D46).withAlphaComponent(0.25)
        sun.eulerAngles = SCNVector3(-0.9, -0.5, -0.2)
        scene.rootNode.addChildNode(sun)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = NSColor(hex: 0xFFF1DA)
        ambient.light?.intensity = 650
        scene.rootNode.addChildNode(ambient)
        _ = box(200, 0.1, 200, color: 0xE9E3D7, at: SCNVector3(0, -0.35, 0))
        _ = box(10.8, 0.13, 6.9, color: 0x6D7963, at: SCNVector3(0, -0.12, 0))
        _ = box(5.25, 0.13, 6.55, color: 0xE7DCC0, at: SCNVector3(-2.65, -0.01, 0))
        _ = box(5.25, 0.13, 6.55, color: 0xF5EDD9, at: SCNVector3(2.65, -0.01, 0))
        // Fine page edges, a stitched spine, and a fabric bookmark.
        for i in 0..<4 {
            _ = box(
                10.45, 0.012, 0.014, color: 0xCFC4AA,
                at: SCNVector3(0, -0.055 + Double(i) * 0.025, 3.275))
        }
        _ = box(0.026, 0.013, 6.3, color: 0xCCBE9E, at: SCNVector3(0, 0.071, 0))
        for i in 0..<13 {
            _ = box(0.08, 0.008, 0.025, color: 0xB8A984, at: SCNVector3(0, 0.08, -2.8 + Double(i) * 0.43))
        }
        _ = box(0.34, 0.012, 1.05, color: 0xBD7958, at: SCNVector3(3.4, -0.16, 3.48))
        // A winding pathway made of separate paper stepping stones on the page.
        for i in 0..<8 {
            let n = paper.cut(
                paper.ellipse(0.45 - Double(i) * 0.015, 0.25), i % 2 == 0 ? 0xD8CCAB : 0xE1D6BA,
                scene.rootNode, x: 0.65 - Double(i) * 0.18, y: 0.09, z: 0.65 + Double(i) * 0.28)
            n.eulerAngles.x = -.pi / 2
        }
        let horizon = hinge(x: 0, z: -2.45, start: 0.02, end: 0.60)
        paper.cut(
            paper.polygon([
                (-4.6, 0), (-4.6, 0.55), (-3.2, 2.45), (-2.5, 1.75), (-1.25, 3.25), (0, 1.9), (1.3, 2.7),
                (2.9, 1.55), (3.7, 2.15), (4.6, 0.7), (4.6, 0),
            ]), 0xBDCAC0, horizon)
        paper.cut(
            paper.polygon([
                (-4.5, 0), (-4.5, 0.32), (-2.75, 1.7), (-1.3, 0.8), (0.35, 2.0), (1.75, 1.0), (3.4, 1.8),
                (4.5, 0.4), (4.5, 0),
            ]), 0x9BAF9F, horizon, z: 0.05)
        let sunDisc = paper.cut(paper.ellipse(0.95, 0.95), 0xEBC78E, horizon, x: -2.5, y: 2.7, z: -0.07)
        sunDisc.castsShadow = false
        for (x, z, h, c) in [
            (-3.6, -1.7, 3.4, 0x526F5B), (-2.2, -1.9, 3.0, 0x738B65),
            (2.15, -1.7, 3.6, 0x5C7964), (3.75, -1.2, 2.8, 0x7C936B), (-4.25, 0.0, 2.3, 0x8D9D70),
            (3.65, 1.1, 2.2, 0x617B59),
        ] {
            tree(x: x, z: z, height: h, color: c)
        }
        let houseHinge = hinge(x: 0.65, z: 0.1, start: 0.18, end: 0.86)
        houseHinge.addChildNode(house)
        buildHouse()
        // Foreground seed heads, grasses and small white paper flowers.
        for (x, z, s) in [(-3.4, 2.1, 1.0), (-2.6, 2.6, 0.65), (2.8, 2.35, 0.8), (4.1, 2.0, 0.75)] {
            let n = hinge(x: x, z: z, start: 0.35, end: 0.95)
            grass(parent: n, scale: s)
        }
        let entry = SCNNode()
        entry.position = SCNVector3(1.35, 0.14, 0.42)
        scene.rootNode.addChildNode(entry)
        let resting = SCNNode()
        resting.position = SCNVector3(-1.45, 0.14, 2.07)
        scene.rootNode.addChildNode(resting)
        peek.position = SCNVector3(-0.65, 1.47, 0.145)
        house.addChildNode(peek)
        anchorNodes = [.entry: entry, .resting: resting, .peek: peek]
    }
    private func tree(x: Double, z: Double, height h: Double, color: Int) {
        let n = hinge(x: x, z: z, start: 0.1, end: 0.76)
        paper.cut(paper.polygon([(-0.11, 0), (-0.07, h * 0.8), (0.07, h * 0.8), (0.14, 0)]), 0x897456, n)
        let crown = SCNNode()
        n.addChildNode(crown)
        foliage.append(crown)
        // Scalloped broadleaf crown with intentionally irregular paper contour.
        let p = NSBezierPath()
        p.move(to: NSPoint(x: -0.9, y: h * 0.42))
        p.curve(
            to: NSPoint(x: -0.62, y: h * 0.82), controlPoint1: NSPoint(x: -1.35, y: h * 0.62),
            controlPoint2: NSPoint(x: -0.98, y: h * 0.85))
        p.curve(
            to: NSPoint(x: 0.22, y: h), controlPoint1: NSPoint(x: -0.65, y: h * 1.07),
            controlPoint2: NSPoint(x: 0, y: h * 1.06))
        p.curve(
            to: NSPoint(x: 0.85, y: h * 0.7), controlPoint1: NSPoint(x: 0.75, y: h * 1.03),
            controlPoint2: NSPoint(x: 1.15, y: h * 0.87))
        p.curve(
            to: NSPoint(x: 0.65, y: h * 0.39), controlPoint1: NSPoint(x: 1.35, y: h * 0.48),
            controlPoint2: NSPoint(x: 0.93, y: h * 0.36))
        p.curve(
            to: NSPoint(x: -0.9, y: h * 0.42), controlPoint1: NSPoint(x: 0, y: h * 0.3),
            controlPoint2: NSPoint(x: -0.5, y: h * 0.34))
        p.close()
        paper.cut(p, color, crown, z: 0.018, thickness: 0.04)
        paper.cut(
            paper.polygon([(-0.025, h * 0.25), (-0.025, h * 0.84), (0.015, h * 0.84), (0.025, h * 0.25)]),
            0xA6B28A,
            crown, z: 0.052)
        for i in 0..<4 {
            let y = h * (0.44 + Double(i) * 0.09)
            let side = i % 2 == 0 ? -1.0 : 1.0
            paper.cut(
                paper.polygon([(0, y), (side * 0.43, y + 0.22), (side * 0.44, y + 0.25), (0, y + 0.04)]),
                0xA6B28A,
                crown, z: 0.053)
        }
    }
    private func grass(parent n: SCNNode, scale: Double) {
        let p = paper.polygon([
            (-0.6, 0), (-0.72, 0.52), (-0.45, 0.28), (-0.42, 0.78), (-0.15, 0.4), (0, 0.98), (0.14, 0.36),
            (0.43, 0.7), (0.4, 0.2), (0.65, 0.43), (0.57, 0),
        ])
        paper.cut(p, 0x89966A, n)
        n.scale = SCNVector3(scale, scale, scale)
        for i in 0..<3 {
            let x = Double(i - 1) * 0.27
            paper.cut(paper.rounded(-0.012, 0, 0.024, 0.6, 0.01), 0x65774E, n, x: x, z: 0.04)
            for j in 0..<5 {
                let a = Double(j) * 2 * .pi / 5
                paper.cut(
                    paper.ellipse(0.105, 0.15), 0xF7E9CA, n, x: x + sin(a) * 0.07, y: 0.62 + cos(a) * 0.07,
                    z: 0.06)
            }
            paper.cut(paper.ellipse(0.075, 0.075), 0xD6AE63, n, x: x, y: 0.62, z: 0.08)
        }
    }
    private func buildHouse() {
        paper.cut(
            paper.polygon([(-1.5, 0), (-1.5, 2.15), (0, 3.15), (1.5, 2.15), (1.5, 0)]), 0xC59B70, house,
            thickness: 0.07)
        // Slightly staggered planks and narrow seams make the paper surface tactile.
        for i in 0..<9 {
            let y = 0.13 + Double(i) * 0.215
            paper.cut(paper.rounded(-1.4, y, 2.8, 0.015, 0.006), 0xB68B62, house, z: 0.041, thickness: 0.005)
        }
        paper.cut(
            paper.polygon([(-1.72, 2.07), (-0.03, 3.3), (1.75, 2.07), (1.52, 1.98), (0, 3.03), (-1.5, 1.98)]),
            0x815D49, house, z: 0.07, thickness: 0.055)
        paper.cut(
            paper.polygon([(-1.3, 2.25), (-0.03, 3.18), (1.33, 2.23), (1.24, 2.18), (0, 3.04), (-1.21, 2.17)]
            ),
            0xA57556, house, z: 0.105)
        paper.cut(paper.rounded(0.74, 2.57, 0.31, 0.65, 0.025), 0x997861, house, z: -0.03)
        paper.cut(paper.rounded(0.69, 3.13, 0.4, 0.1, 0.02), 0x7D6351, house, z: 0.01)
        // Rounded doorway is a dark cutout-looking contour with an oak frame.
        paper.cut(paper.rounded(0.26, 0, 0.88, 1.62, 0.35), 0x8B6B50, house, z: 0.09)
        paper.cut(paper.rounded(0.34, 0.01, 0.72, 1.47, 0.3), 0x494D3D, house, z: 0.12)
        paper.cut(paper.rounded(-1.15, 1.1, 0.98, 0.99, 0.1), 0x87684E, house, z: 0.09)
        paper.cut(paper.rounded(-1.06, 1.19, 0.8, 0.81, 0.05), 0xEACB8D, house, z: 0.12)
        paper.cut(paper.rounded(-0.69, 1.18, 0.055, 0.83, 0.005), 0x87684E, house, z: 0.18)
        paper.cut(paper.rounded(-1.07, 1.58, 0.83, 0.055, 0.005), 0x87684E, house, z: 0.18)
        paper.cut(paper.rounded(-1.22, 1.08, 1.12, 0.12, 0.02), 0xB48B63, house, z: 0.2)
        paper.cut(paper.rounded(1.18, 1.53, 0.23, 0.32, 0.025), 0x655D46, house, z: 0.1)
        house.addChildNode(lamp)
        paper.cut(paper.rounded(1.22, 1.57, 0.15, 0.23, 0.015), 0xFFE0A0, lamp, z: 0.14)
        // Little paper mushrooms near the door.
        for (x, y) in [(-1.2, 0.0), (-1.0, 0.0)] {
            paper.cut(paper.rounded(-0.025, 0, 0.05, 0.16, 0.02), cream, house, x: x, y: y, z: 0.16)
            paper.cut(paper.ellipse(0.22, 0.11), 0xA5674E, house, x: x, y: y + 0.16, z: 0.18)
        }
    }

    public func update(in context: WorldContext, events: [CharacterEvent]) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        SCNTransaction.disableActions = true
        for (node, start, end) in hinges {
            node.eulerAngles.x = CGFloat(Double.pi / 2 * (1 - smoothstep(start, end, context.progress)))
        }
        for (i, node) in foliage.enumerated() {
            node.eulerAngles.z = CGFloat(sin(context.clock * 0.65 + Double(i)) * 0.012 * context.progress)
        }
        for event in events {
            switch event {
            case .returningInside: returning = true
            case .restingInside, .appearing, .outside: returning = false
            }
        }
        lamp.opacity = returning || context.progress < 0.65 ? 1 : 0.25
        SCNTransaction.commit()
    }
}
