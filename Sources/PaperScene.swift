import AppKit
import SceneKit

extension NSColor {
    convenience init(hex: Int) {
        self.init(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                  green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

/// Original vector-cut paper artwork, built as extruded contours, not alpha rectangles.
final class PaperWorld {
    let scene = SCNScene()
    let camera = SCNNode()
    private var hinges: [(SCNNode, Double, Double)] = []
    private let house = SCNNode()
    private let cat = SCNNode()
    private let catBody = SCNNode()
    private let head = SCNNode()
    private let tail = SCNNode()
    private let frontPaw = SCNNode()
    private let otherPaw = SCNNode()
    private var eyes: [SCNNode] = []
    private let windowCat = SCNNode()
    private let lamp = SCNNode()
    private var foliage: [SCNNode] = []
    private var catYaw = 0.0
    private var lastSceneClock = 0.0
    private var materials: [Int: SCNMaterial] = [:]
    private let cream = 0xF4E9CD, orange = 0xC77C46, ink = 0x443D32

    init() { build() }
    private func material(_ hex: Int) -> SCNMaterial {
        if let m = materials[hex] { return m }
        let m = SCNMaterial()
        m.diffuse.contents = NSColor(hex: hex); m.roughness.contents = 0.95
        m.lightingModel = .physicallyBased; m.isDoubleSided = true
        materials[hex] = m; return m
    }
    @discardableResult
    private func cut(_ path: NSBezierPath, _ color: Int, _ parent: SCNNode, x: Double = 0, y: Double = 0,
                     z: Double = 0, thickness: Double = 0.025, name: String? = nil) -> SCNNode {
        path.flatness = 0.015
        let geo = SCNShape(path: path, extrusionDepth: thickness)
        geo.chamferRadius = 0.007; geo.materials = [material(color)]
        let node = SCNNode(geometry: geo); node.position = SCNVector3(x, y, z); node.name = name
        node.castsShadow = true; parent.addChildNode(node); return node
    }
    private func polygon(_ points: [(Double, Double)]) -> NSBezierPath {
        let p = NSBezierPath(); guard let first = points.first else { return p }
        p.move(to: NSPoint(x: first.0, y: first.1))
        for pt in points.dropFirst() { p.line(to: NSPoint(x: pt.0, y: pt.1)) }; p.close(); return p
    }
    private func ellipse(_ w: Double, _ h: Double) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: -w / 2, y: -h / 2, width: w, height: h))
    }
    private func rounded(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) -> NSBezierPath {
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
    }
    private func hinge(x: Double, z: Double, start: Double, end: Double) -> SCNNode {
        let n = SCNNode(); n.position = SCNVector3(x, 0.13 + Double(hinges.count) * 0.003, z)
        scene.rootNode.addChildNode(n); hinges.append((n, start, end)); return n
    }
    private func box(_ w: Double, _ h: Double, _ l: Double, color: Int, at p: SCNVector3) -> SCNNode {
        let g = SCNBox(width: w, height: h, length: l, chamferRadius: 0.045); g.materials = [material(color)]
        let n = SCNNode(geometry: g); n.position = p; scene.rootNode.addChildNode(n); return n
    }
    private func build() {
        scene.background.contents = NSColor(hex: 0xE9E3D7)
        scene.lightingEnvironment.intensity = 0.6
        camera.camera = SCNCamera(); camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 6.5
        camera.camera?.zNear = 0.1; camera.camera?.zFar = 100
        camera.camera?.wantsHDR = false
        camera.position = SCNVector3(5.6, 8.8, 16.5); camera.look(at: SCNVector3(0, 0.7, 0))
        scene.rootNode.addChildNode(camera)
        let sun = SCNNode(); sun.light = SCNLight(); sun.light?.type = .directional
        sun.light?.intensity = 1550; sun.light?.temperature = 5100
        sun.light?.castsShadow = true; sun.light?.shadowMode = .deferred
        sun.light?.shadowRadius = 5; sun.light?.shadowSampleCount = 16
        sun.light?.shadowColor = NSColor(hex: 0x645D46).withAlphaComponent(0.25)
        sun.eulerAngles = SCNVector3(-0.9, -0.5, -0.2); scene.rootNode.addChildNode(sun)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.color = NSColor(hex: 0xFFF1DA); ambient.light?.intensity = 650
        scene.rootNode.addChildNode(ambient)
        _ = box(200, 0.1, 200, color: 0xE9E3D7, at: SCNVector3(0, -0.35, 0))
        _ = box(10.8, 0.13, 6.9, color: 0x6D7963, at: SCNVector3(0, -0.12, 0))
        _ = box(5.25, 0.13, 6.55, color: 0xE7DCC0, at: SCNVector3(-2.65, -0.01, 0))
        _ = box(5.25, 0.13, 6.55, color: 0xF5EDD9, at: SCNVector3(2.65, -0.01, 0))
        // Fine page edges, a stitched spine, and a fabric bookmark.
        for i in 0..<4 {
            _ = box(10.45, 0.012, 0.014, color: 0xCFC4AA,
                    at: SCNVector3(0, -0.055 + Double(i) * 0.025, 3.275))
        }
        _ = box(0.026, 0.013, 6.3, color: 0xCCBE9E, at: SCNVector3(0, 0.071, 0))
        for i in 0..<13 {
            _ = box(0.08, 0.008, 0.025, color: 0xB8A984, at: SCNVector3(0, 0.08, -2.8 + Double(i) * 0.43))
        }
        _ = box(0.34, 0.012, 1.05, color: 0xBD7958, at: SCNVector3(3.4, -0.16, 3.48))
        // A winding pathway made of separate paper stepping stones on the page.
        for i in 0..<8 {
            let n = cut(ellipse(0.45 - Double(i) * 0.015, 0.25), i % 2 == 0 ? 0xD8CCAB : 0xE1D6BA,
                        scene.rootNode, x: 0.65 - Double(i) * 0.18, y: 0.09, z: 0.65 + Double(i) * 0.28)
            n.eulerAngles.x = -.pi / 2
        }
        let horizon = hinge(x: 0, z: -2.45, start: 0.02, end: 0.60)
        cut(polygon([(-4.6,0),(-4.6,0.55),(-3.2,2.45),(-2.5,1.75),(-1.25,3.25),(0,1.9),(1.3,2.7),(2.9,1.55),(3.7,2.15),(4.6,0.7),(4.6,0)]), 0xBDCAC0, horizon)
        cut(polygon([(-4.5,0),(-4.5,0.32),(-2.75,1.7),(-1.3,0.8),(0.35,2.0),(1.75,1.0),(3.4,1.8),(4.5,0.4),(4.5,0)]), 0x9BAF9F, horizon, z: 0.05)
        let sunDisc = cut(ellipse(0.95, 0.95), 0xEBC78E, horizon, x: -2.5, y: 2.7, z: -0.07)
        sunDisc.castsShadow = false
        for (x,z,h,c) in [(-3.6,-1.7,3.4,0x526F5B),(-2.2,-1.9,3.0,0x738B65),
                          (2.15,-1.7,3.6,0x5C7964),(3.75,-1.2,2.8,0x7C936B),(-4.25,0.0,2.3,0x8D9D70),
                          (3.65,1.1,2.2,0x617B59)] {
            tree(x: x, z: z, height: h, color: c)
        }
        let houseHinge = hinge(x: 0.65, z: 0.1, start: 0.18, end: 0.86)
        houseHinge.addChildNode(house)
        buildHouse()
        // Foreground seed heads, grasses and small white paper flowers.
        for (x,z,s) in [(-3.4,2.1,1.0),(-2.6,2.6,0.65),(2.8,2.35,0.8),(4.1,2.0,0.75)] {
            let n = hinge(x: x, z: z, start: 0.35, end: 0.95)
            grass(parent: n, scale: s)
        }
        scene.rootNode.addChildNode(cat); buildCat()
        update(BookState())
    }
    private func tree(x: Double, z: Double, height h: Double, color: Int) {
        let n = hinge(x: x, z: z, start: 0.1, end: 0.76)
        cut(polygon([(-0.11,0),(-0.07,h*0.8),(0.07,h*0.8),(0.14,0)]), 0x897456, n)
        let crown = SCNNode(); n.addChildNode(crown); foliage.append(crown)
        // Scalloped broadleaf crown with intentionally irregular paper contour.
        let p = NSBezierPath(); p.move(to: NSPoint(x: -0.9, y: h*0.42))
        p.curve(to: NSPoint(x: -0.62,y:h*0.82), controlPoint1: NSPoint(x:-1.35,y:h*0.62), controlPoint2:NSPoint(x:-0.98,y:h*0.85))
        p.curve(to: NSPoint(x: 0.22,y:h), controlPoint1:NSPoint(x:-0.65,y:h*1.07), controlPoint2:NSPoint(x:0,y:h*1.06))
        p.curve(to: NSPoint(x:0.85,y:h*0.7), controlPoint1:NSPoint(x:0.75,y:h*1.03), controlPoint2:NSPoint(x:1.15,y:h*0.87))
        p.curve(to: NSPoint(x:0.65,y:h*0.39), controlPoint1:NSPoint(x:1.35,y:h*0.48), controlPoint2:NSPoint(x:0.93,y:h*0.36))
        p.curve(to:NSPoint(x:-0.9,y:h*0.42),controlPoint1:NSPoint(x:0,y:h*0.3),controlPoint2:NSPoint(x:-0.5,y:h*0.34));p.close()
        cut(p, color, crown, z: 0.018, thickness: 0.04)
        cut(polygon([(-0.025,h*0.25),(-0.025,h*0.84),(0.015,h*0.84),(0.025,h*0.25)]), 0xA6B28A, crown, z: 0.052)
        for i in 0..<4 {
            let y = h * (0.44 + Double(i) * 0.09), side = i % 2 == 0 ? -1.0 : 1.0
            cut(polygon([(0,y),(side*0.43,y+0.22),(side*0.44,y+0.25),(0,y+0.04)]), 0xA6B28A, crown, z:0.053)
        }
    }
    private func grass(parent n: SCNNode, scale: Double) {
        let p = polygon([(-0.6,0),(-0.72,0.52),(-0.45,0.28),(-0.42,0.78),(-0.15,0.4),(0,0.98),(0.14,0.36),(0.43,0.7),(0.4,0.2),(0.65,0.43),(0.57,0)])
        cut(p, 0x89966A, n); n.scale = SCNVector3(scale,scale,scale)
        for i in 0..<3 {
            let x = Double(i-1)*0.27
            cut(rounded(-0.012,0,0.024,0.6,0.01),0x65774E,n,x:x,z:0.04)
            for j in 0..<5 {
                let a = Double(j)*2 * .pi/5
                cut(ellipse(0.105,0.15),0xF7E9CA,n,x:x+sin(a)*0.07,y:0.62+cos(a)*0.07,z:0.06)
            }
            cut(ellipse(0.075,0.075),0xD6AE63,n,x:x,y:0.62,z:0.08)
        }
    }
    private func buildHouse() {
        cut(polygon([(-1.5,0),(-1.5,2.15),(0,3.15),(1.5,2.15),(1.5,0)]), 0xC59B70, house, thickness:0.07)
        // Slightly staggered planks and narrow seams make the paper surface tactile.
        for i in 0..<9 {
            let y = 0.13 + Double(i)*0.215
            cut(rounded(-1.4,y,2.8,0.015,0.006),0xB68B62,house,z:0.041,thickness:0.005)
        }
        cut(polygon([(-1.72,2.07),(-0.03,3.3),(1.75,2.07),(1.52,1.98),(0,3.03),(-1.5,1.98)]),0x815D49,house,z:0.07,thickness:0.055)
        cut(polygon([(-1.3,2.25),(-0.03,3.18),(1.33,2.23),(1.24,2.18),(0,3.04),(-1.21,2.17)]),0xA57556,house,z:0.105)
        cut(rounded(0.74,2.57,0.31,0.65,0.025),0x997861,house,z:-0.03)
        cut(rounded(0.69,3.13,0.4,0.1,0.02),0x7D6351,house,z:0.01)
        // Rounded doorway is a dark cutout-looking contour with an oak frame.
        cut(rounded(0.26,0,0.88,1.62,0.35),0x8B6B50,house,z:0.09)
        cut(rounded(0.34,0.01,0.72,1.47,0.3),0x494D3D,house,z:0.12)
        cut(rounded(-1.15,1.1,0.98,0.99,0.1),0x87684E,house,z:0.09)
        cut(rounded(-1.06,1.19,0.8,0.81,0.05),0xEACB8D,house,z:0.12)
        cut(rounded(-0.69,1.18,0.055,0.83,0.005),0x87684E,house,z:0.18)
        cut(rounded(-1.07,1.58,0.83,0.055,0.005),0x87684E,house,z:0.18)
        house.addChildNode(windowCat); windowCat.position = SCNVector3(-0.65,1.47,0.145)
        cut(ellipse(0.32,0.29),orange,windowCat)
        for x in [-0.06,0.06] { cut(rounded(-0.026,0,0.052,0.018,0.008),ink,windowCat,x:x,y:0.02,z:0.025) }
        cut(polygon([(-0.14,0.02),(-0.14,0.25),(-0.01,0.12)]),orange,windowCat)
        cut(polygon([(0.14,0.02),(0.14,0.25),(0.01,0.12)]),orange,windowCat)
        cut(rounded(-1.22,1.08,1.12,0.12,0.02),0xB48B63,house,z:0.2)
        cut(rounded(1.18,1.53,0.23,0.32,0.025),0x655D46,house,z:0.1)
        house.addChildNode(lamp)
        cut(rounded(1.22,1.57,0.15,0.23,0.015),0xFFE0A0,lamp,z:0.14)
        // Little paper mushrooms near the door.
        for (x,y) in [(-1.2,0.0),(-1.0,0.0)] {
            cut(rounded(-0.025,0,0.05,0.16,0.02),cream,house,x:x,y:y,z:0.16)
            cut(ellipse(0.22,0.11),0xA5674E,house,x:x,y:y+0.16,z:0.18)
        }
    }
    private func buildCat() {
        cat.name = "cat"; cat.addChildNode(catBody)
        catBody.addChildNode(tail); tail.position = SCNVector3(0.2,0.25,-0.035)
        let t = NSBezierPath(); t.move(to:NSPoint(x:0,y:0))
        t.curve(to:NSPoint(x:0.43,y:0.52),controlPoint1:NSPoint(x:0.55,y:-0.02),controlPoint2:NSPoint(x:0.66,y:0.22))
        t.curve(to:NSPoint(x:0.29,y:0.4),controlPoint1:NSPoint(x:0.3,y:0.68),controlPoint2:NSPoint(x:0.18,y:0.51))
        t.curve(to:NSPoint(x:0,y:0.14),controlPoint1:NSPoint(x:0.51,y:0.16),controlPoint2:NSPoint(x:0.27,y:0.1));t.close()
        cut(t,orange,tail,name:"cat")
        cut(ellipse(0.54,0.7),orange,catBody,y:0.45,name:"cat")
        cut(ellipse(0.31,0.49),cream,catBody,x:-0.07,y:0.35,z:0.034,name:"cat")
        catBody.addChildNode(head); head.position = SCNVector3(-0.04,0.84,0.045)
        cut(ellipse(0.67,0.5),orange,head,name:"cat")
        cut(polygon([(-0.29,0.06),(-0.32,0.4),(-0.08,0.21)]),orange,head,name:"cat")
        cut(polygon([(0.27,0.06),(0.31,0.4),(0.08,0.21)]),orange,head,name:"cat")
        cut(polygon([(-0.255,0.17),(-0.275,0.32),(-0.15,0.22)]),0xDCAD96,head,z:0.018)
        cut(polygon([(0.24,0.17),(0.27,0.32),(0.15,0.22)]),0xDCAD96,head,z:0.018)
        cut(ellipse(0.47,0.25),cream,head,y:-0.10,z:0.025,name:"cat")
        for x in [-0.135,0.135] { eyes.append(cut(ellipse(0.046,0.072),ink,head,x:x,y:0.015,z:0.05)) }
        cut(polygon([(-0.04,-0.075),(0.04,-0.075),(0,-0.12)]),0x9C6658,head,z:0.055)
        for i in 0..<3 {
            cut(rounded(-0.018,0,0.036,0.09,0.01),0xA76537,head,x:Double(i-1)*0.085,y:0.14,z:0.035)
        }
        for side in [-1.0,1.0] {
            for i in 0..<2 {
                cut(polygon([(side*0.18,-0.09-Double(i)*0.04),(side*0.4,-0.065-Double(i)*0.08),(side*0.4,-0.075-Double(i)*0.08)]),0x88735D,head,z:0.048)
            }
        }
        catBody.addChildNode(frontPaw); frontPaw.position = SCNVector3(-0.19,0.22,0.065)
        cut(rounded(-0.075,-0.22,0.15,0.32,0.065),cream,frontPaw,name:"cat")
        catBody.addChildNode(otherPaw); otherPaw.position = SCNVector3(0.15,0.22,0.065)
        cut(rounded(-0.075,-0.22,0.15,0.32,0.065),cream,otherPaw,name:"cat")
    }
    func update(_ s: BookState) {
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0; SCNTransaction.disableActions = true
        for (node,start,end) in hinges { node.eulerAngles.x = CGFloat(Double.pi / 2 * (1 - smoothstep(start,end,s.progress))) }
        for (i,n) in foliage.enumerated() { n.eulerAngles.z = CGFloat(sin(s.clock*0.65+Double(i))*0.012*s.progress) }
        let turnDelta = clamp(s.clock-lastSceneClock,0,0.05)
        lastSceneClock = s.clock
        let facing = s.mood == .returning ? Double.pi : 0
        catYaw += (facing-catYaw) * (1-exp(-turnDelta/0.10))
        catBody.eulerAngles.y = CGFloat(catYaw)
        let walking = s.mood == .walking || s.mood == .returning
        let step = walking ? sin(s.clock*12)*0.04 : 0
        cat.position = SCNVector3(1.35 - s.outside*2.8, 0.14+abs(step), 0.42+s.outside*1.65)
        let visibleOutside = (s.mood == .stretching || s.mood == .walking) ? max(0.16,s.outside) : s.outside
        let appear = smoothstep(0.03,0.22,visibleOutside) * smoothstep(0.42,0.62,s.progress)
        let stretchFade = s.mood == .stretching ? smoothstep(0,0.25,s.moodTime) : 1
        cat.opacity = CGFloat(appear * stretchFade); cat.isHidden = appear * stretchFade < 0.005
        // Grow naturally from the door; reversing preserves position and scale.
        cat.scale = SCNVector3(0.96,0.96,0.96)
        cat.eulerAngles.x = CGFloat(Double.pi / 2 * (1-smoothstep(0.4,0.82,s.progress)))
        let stretch = s.mood == .stretching ? sin(min(1,s.moodTime/1.1)*Double.pi) : 0
        catBody.scale = SCNVector3(1+stretch*0.18,1-stretch*0.17,1)
        head.eulerAngles.z = CGFloat(s.mood == .greeting ? sin(s.moodTime*4)*0.12 : sin(s.clock*0.7)*0.025)
        tail.eulerAngles.z = CGFloat(sin(s.clock*1.8)*0.2)
        frontPaw.eulerAngles.z = CGFloat(s.mood == .greeting ? -0.9-0.25*sin(s.moodTime*11) : (walking ? sin(s.clock*12)*0.3 : 0))
        frontPaw.position.y = s.mood == .greeting ? 0.44 : 0.22
        otherPaw.eulerAngles.z = CGFloat(walking ? -sin(s.clock*12)*0.3 : 0)
        for eye in eyes { eye.scale.y = CGFloat(max(0.08,1-s.blink)) }
        windowCat.isHidden = s.outside > 0.12 || s.progress < 0.38 || s.mood == .stretching || s.mood == .walking
        windowCat.position.y = CGFloat(1.39 + smoothstep(0.4,0.83,s.progress)*0.15 + stretch*0.1)
        windowCat.eulerAngles.z = CGFloat(sin(s.clock)*0.04)
        let lit = s.mood == .returning || s.progress < 0.65
        lamp.opacity = lit ? 1 : 0.25
        SCNTransaction.commit()
    }
}
