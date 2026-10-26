import AppKit
import PaperCatBehavior
import PopupBookCore
import SceneKit
import SceneKitRendering

@MainActor public final class PaperCatPresenter: CharacterPresenter {
    private let paper = PaperGeometry()
    public let cat = SCNNode()
    public let windowCat = SCNNode()
    private let entry: SCNNode
    private let resting: SCNNode
    private let catBody = SCNNode(), head = SCNNode(), tail = SCNNode(), frontPaw = SCNNode(),
        otherPaw = SCNNode()
    private var eyes: [SCNNode] = []
    private var catYaw = 0.0, lastSceneClock = 0.0
    private let cream = 0xF4E9CD, orange = 0xC77C46, ink = 0x443D32
    public init(stage: SceneStage) throws {
        entry = try stage.anchor(.entry)
        resting = try stage.anchor(.resting)
        let peek = try stage.anchor(.peek)
        stage.scene.rootNode.addChildNode(cat)
        peek.addChildNode(windowCat)
        buildCat()
        buildPeek()
    }
    private func buildPeek() {
        paper.cut(paper.ellipse(0.32, 0.29), orange, windowCat)
        for x in [-0.06, 0.06] {
            paper.cut(paper.rounded(-0.026, 0, 0.052, 0.018, 0.008), ink, windowCat, x: x, y: 0.02, z: 0.025)
        }
        paper.cut(paper.polygon([(-0.14, 0.02), (-0.14, 0.25), (-0.01, 0.12)]), orange, windowCat)
        paper.cut(paper.polygon([(0.14, 0.02), (0.14, 0.25), (0.01, 0.12)]), orange, windowCat)
    }
    private func buildCat() {
        cat.addChildNode(catBody)
        catBody.addChildNode(tail)
        tail.position = SCNVector3(0.2, 0.25, -0.035)
        let t = NSBezierPath()
        t.move(to: NSPoint(x: 0, y: 0))
        t.curve(
            to: NSPoint(x: 0.43, y: 0.52), controlPoint1: NSPoint(x: 0.55, y: -0.02),
            controlPoint2: NSPoint(x: 0.66, y: 0.22))
        t.curve(
            to: NSPoint(x: 0.29, y: 0.4), controlPoint1: NSPoint(x: 0.3, y: 0.68),
            controlPoint2: NSPoint(x: 0.18, y: 0.51))
        t.curve(
            to: NSPoint(x: 0, y: 0.14), controlPoint1: NSPoint(x: 0.51, y: 0.16),
            controlPoint2: NSPoint(x: 0.27, y: 0.1))
        t.close()
        paper.cut(t, orange, tail)
        paper.cut(paper.ellipse(0.54, 0.7), orange, catBody, y: 0.45)
        paper.cut(paper.ellipse(0.31, 0.49), cream, catBody, x: -0.07, y: 0.35, z: 0.034)
        catBody.addChildNode(head)
        head.position = SCNVector3(-0.04, 0.84, 0.045)
        paper.cut(paper.ellipse(0.67, 0.5), orange, head)
        paper.cut(paper.polygon([(-0.29, 0.06), (-0.32, 0.4), (-0.08, 0.21)]), orange, head)
        paper.cut(paper.polygon([(0.27, 0.06), (0.31, 0.4), (0.08, 0.21)]), orange, head)
        paper.cut(paper.polygon([(-0.255, 0.17), (-0.275, 0.32), (-0.15, 0.22)]), 0xDCAD96, head, z: 0.018)
        paper.cut(paper.polygon([(0.24, 0.17), (0.27, 0.32), (0.15, 0.22)]), 0xDCAD96, head, z: 0.018)
        paper.cut(paper.ellipse(0.47, 0.25), cream, head, y: -0.10, z: 0.025)
        for x in [-0.135, 0.135] {
            eyes.append(paper.cut(paper.ellipse(0.046, 0.072), ink, head, x: x, y: 0.015, z: 0.05))
        }
        paper.cut(paper.polygon([(-0.04, -0.075), (0.04, -0.075), (0, -0.12)]), 0x9C6658, head, z: 0.055)
        for i in 0..<3 {
            paper.cut(
                paper.rounded(-0.018, 0, 0.036, 0.09, 0.01), 0xA76537, head, x: Double(i - 1) * 0.085,
                y: 0.14,
                z: 0.035)
        }
        for side in [-1.0, 1.0] {
            for i in 0..<2 {
                paper.cut(
                    paper.polygon([
                        (side * 0.18, -0.09 - Double(i) * 0.04), (side * 0.4, -0.065 - Double(i) * 0.08),
                        (side * 0.4, -0.075 - Double(i) * 0.08),
                    ]), 0x88735D, head, z: 0.048)
            }
        }
        catBody.addChildNode(frontPaw)
        frontPaw.position = SCNVector3(-0.19, 0.22, 0.065)
        paper.cut(paper.rounded(-0.075, -0.22, 0.15, 0.32, 0.065), cream, frontPaw)
        catBody.addChildNode(otherPaw)
        otherPaw.position = SCNVector3(0.15, 0.22, 0.065)
        paper.cut(paper.rounded(-0.075, -0.22, 0.15, 0.32, 0.065), cream, otherPaw)
    }

    public func update(_ pose: CatPose, in context: WorldContext) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        SCNTransaction.disableActions = true
        let turnDelta = clamp(context.clock - lastSceneClock, 0, 0.05)
        lastSceneClock = context.clock
        let facing = pose.mood == .returning ? Double.pi : 0
        catYaw += (facing - catYaw) * (1 - exp(-turnDelta / 0.10))
        catBody.eulerAngles.y = CGFloat(catYaw)
        let walking = pose.mood == .walking || pose.mood == .returning
        let step = walking ? sin(context.clock * 12) * 0.04 : 0
        let a = entry.worldPosition
        let b = resting.worldPosition
        let p = CGFloat(pose.outside)
        cat.position = SCNVector3(
            a.x + (b.x - a.x) * p, a.y + (b.y - a.y) * p + CGFloat(abs(step)), a.z + (b.z - a.z) * p)
        let visibleOutside =
            (pose.mood == .stretching || pose.mood == .walking) ? max(0.16, pose.outside) : pose.outside
        let appear = smoothstep(0.03, 0.22, visibleOutside) * smoothstep(0.42, 0.62, context.progress)
        let stretchFade = pose.mood == .stretching ? smoothstep(0, 0.25, pose.moodTime) : 1
        cat.opacity = CGFloat(appear * stretchFade)
        cat.isHidden = appear * stretchFade < 0.005
        // Grow naturally from the door; reversing preserves position and scale.
        cat.scale = SCNVector3(0.96, 0.96, 0.96)
        cat.eulerAngles.x = CGFloat(Double.pi / 2 * (1 - smoothstep(0.4, 0.82, context.progress)))
        let stretch = pose.mood == .stretching ? sin(min(1, pose.moodTime / 1.1) * Double.pi) : 0
        catBody.scale = SCNVector3(1 + stretch * 0.18, 1 - stretch * 0.17, 1)
        head.eulerAngles.z = CGFloat(
            pose.mood == .greeting ? sin(pose.moodTime * 4) * 0.12 : sin(context.clock * 0.7) * 0.025)
        tail.eulerAngles.z = CGFloat(sin(context.clock * 1.8) * 0.2)
        frontPaw.eulerAngles.z = CGFloat(
            pose.mood == .greeting
                ? -0.9 - 0.25 * sin(pose.moodTime * 11) : (walking ? sin(context.clock * 12) * 0.3 : 0))
        frontPaw.position.y = pose.mood == .greeting ? 0.44 : 0.22
        otherPaw.eulerAngles.z = CGFloat(walking ? -sin(context.clock * 12) * 0.3 : 0)
        for eye in eyes { eye.scale.y = CGFloat(max(0.08, 1 - pose.blink)) }
        windowCat.isHidden =
            pose.outside > 0.12 || context.progress < 0.38 || pose.mood == .stretching
            || pose.mood == .walking
        windowCat.position.y = CGFloat(-0.08 + smoothstep(0.4, 0.83, context.progress) * 0.15 + stretch * 0.1)
        windowCat.eulerAngles.z = CGFloat(sin(context.clock) * 0.04)
        SCNTransaction.commit()
    }
}
