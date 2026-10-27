import Foundation
import PaperCatBehavior
import PopupBookCore
import SceneKit
import SceneKitRendering

public enum VolumeCatError: Error, LocalizedError {
    case missingContactSurface
    public var errorDescription: String? { "立体角色所需的场景落脚表面不可用。" }
}

/// Experimental visual candidate. Default app composition still uses the paper presenter.
/// Grooming, eyelids, petting and window performances need dedicated production assets.
@MainActor public final class VolumeCatPresenter: CharacterPresenter {
    public let root = SCNNode()
    public var lastError: String? { model.lastError }
    public private(set) var usesFallbackAnimation = false
    private let model: SkeletalModel
    private let entry: SCNNode, resting: SCNNode, secondary: SCNNode
    private let stage: SceneStage
    private var yaw = 0.0
    private var placement = SurfacePlacement()
    public init(stage: SceneStage, assets: URL) throws {
        entry = try stage.anchor(.entry)
        resting = try stage.anchor(.resting)
        secondary = try stage.anchor(.secondaryResting)
        guard [entry, resting, secondary].allSatisfy({ stage.contactPoint(below: $0.worldPosition) != nil })
        else { throw VolumeCatError.missingContactSurface }
        self.stage = stage
        let names = ["CatIdle", "CatWalk", "CatSit", "CatTurn"]
        model = try SkeletalModel(
            model: assets.appendingPathComponent("CatIdle.usdz"),
            animations: names.map {
                SceneAnimationAsset(
                    id: SceneAnimationID($0),
                    url: assets.appendingPathComponent($0 + ".usdz"), loops: $0 != "CatSit")
            })
        model.root.position.y = -model.root.boundingBox.min.y * 0.96
        root.addChildNode(model.root)
        stage.scene.rootNode.addChildNode(root)
    }
    public func update(_ pose: CatPose, in context: WorldContext) {
        let clip: String
        switch pose.mood {
        case .walking, .returning, .strolling: clip = "CatWalk"
        case .resting, .settling, .petting: clip = "CatSit"
        case .greeting, .inviting: clip = "CatTurn"
        default: clip = "CatIdle"
        }
        usesFallbackAnimation = [
            .grooming, .petting, .stretching, .waking, .inviting, .greeting, .observing, .settling,
        ].contains(pose.mood)
        _ = model.advance(SceneAnimationID(clip), deltaTime: context.deltaTime)
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        let a = entry.worldPosition
        let b = resting.worldPosition
        let c = secondary.worldPosition
        let p = CGFloat(pose.outside)
        let r = CGFloat(pose.roaming)
        let fold = 1 - smoothstep(0.4, 0.82, context.progress)
        var position = SCNVector3(
            a.x + (b.x - a.x) * p + (c.x - b.x) * r * p,
            a.y + (b.y - a.y) * p, a.z + (b.z - a.z) * p + (c.z - b.z) * r * p)
        position.y = placement.update(at: position, in: stage, deltaTime: context.deltaTime)
        position.y += CGFloat(0.10 * fold)
        root.position = position
        yaw += (pose.facing - yaw) * (1 - exp(-max(0, context.deltaTime) / 0.15))
        root.eulerAngles = SCNVector3(Double.pi / 2 * fold, yaw, 0)
        let visible = pose.mood == .stretching ? max(0.16, pose.outside) : pose.outside
        let appear = smoothstep(0.03, 0.22, visible) * smoothstep(0.42, 0.62, context.progress)
        root.opacity = CGFloat(appear)
        root.isHidden = appear < 0.005
        // Preserve the paper-book mechanism while protecting volume from intersecting the page.
        let depth = max(0.03, smoothstep(0.4, 0.82, context.progress))
        let breath = 1 + sin(context.clock * 1.7) * 0.004
        model.root.scale = SCNVector3(0.96, 0.96 * breath, 0.96 * depth)
        SCNTransaction.commit()
    }
}
