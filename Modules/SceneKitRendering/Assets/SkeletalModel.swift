import Foundation
import SceneKit

public struct SceneAnimationID: Hashable, Sendable {
    public let rawValue: String
    public init(_ value: String) { rawValue = value }
}
public struct SceneAnimationAsset {
    public let id: SceneAnimationID
    public let url: URL
    public let loops: Bool
    public init(id: SceneAnimationID, url: URL, loops: Bool) {
        self.id = id
        self.url = url
        self.loops = loops
    }
}
public enum SkeletalAssetError: Error, LocalizedError {
    case invalidConfiguration(String)
    case missingSkeleton
    case incompatibleSkeleton(String)
    case missingAnimation(String)
    case missingTarget(String)
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let reason): return L10n.text("动作资源配置无效：") + reason
        case .missingSkeleton: return L10n.text("角色资源缺少骨骼或蒙皮。")
        case .incompatibleSkeleton(let id): return L10n.text("动作与模型的骨骼层级不一致：") + id
        case .missingAnimation(let id): return L10n.text("角色资源缺少有效动作：") + id
        case .missingTarget(let name): return L10n.text("动作与模型的目标不匹配：") + name
        }
    }
}

/// A deterministic skeletal player. The external logical clock owns playback and pause.
@MainActor public final class SkeletalModel {
    private struct Clip {
        let bindings: [SCNAnimationPlayer]
        let duration: Double
        let loops: Bool
        var elapsed = 0.0
        var weight = 0.0
    }
    public let root = SCNNode()
    public private(set) var lastError: String?
    private var joints: [SCNNode] = []
    private var clips: [SceneAnimationID: Clip] = [:]
    private var current: SceneAnimationID?
    private var transitionFrom: [SceneAnimationID: Double] = [:]
    private var transitionElapsed = 0.0
    public init(model: URL, animations: [SceneAnimationAsset]) throws {
        guard !animations.isEmpty else {
            throw SkeletalAssetError.invalidConfiguration(L10n.text("至少需要一个动作"))
        }
        var identifiers = Set<SceneAnimationID>()
        for asset in animations {
            guard !asset.id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                identifiers.insert(asset.id).inserted
            else { throw SkeletalAssetError.invalidConfiguration(L10n.text("动作标识为空或重复")) }
        }
        let scene = try SCNScene(url: model, options: [.checkConsistency: true])
        for child in scene.rootNode.childNodes { root.addChildNode(child) }
        root.enumerateChildNodes { node, _ in
            node.removeAllAnimations()
            if let skin = node.skinner { joints += skin.bones }
        }
        guard !joints.isEmpty else { throw SkeletalAssetError.missingSkeleton }
        let expectedSkeleton = try Set(joints.map { try Self.path(of: $0, under: root) })
        for asset in animations {
            let source = try SCNScene(url: asset.url, options: [.checkConsistency: true])
            var sourceJoints: [SCNNode] = []
            source.rootNode.enumerateChildNodes { node, _ in
                if let skin = node.skinner { sourceJoints += skin.bones }
            }
            let sourceSkeleton = try Set(sourceJoints.map { try Self.path(of: $0, under: source.rootNode) })
            guard sourceSkeleton == expectedSkeleton else {
                throw SkeletalAssetError.incompatibleSkeleton(asset.id.rawValue)
            }
            var bindings: [SCNAnimationPlayer] = []
            var duration = 0.0
            var failure: Error?
            @MainActor func attach(_ node: SCNNode) {
                for key in node.animationKeys {
                    guard let original = node.animationPlayer(forKey: key) else { continue }
                    let path: [String]
                    do { path = try Self.path(of: node, under: source.rootNode) } catch {
                        failure = error
                        return
                    }
                    var target = root
                    for name in path {
                        let matches = target.childNodes.filter { $0.name == name }
                        guard matches.count == 1, let child = matches.first else {
                            failure = SkeletalAssetError.missingTarget(path.joined(separator: "/"))
                            return
                        }
                        target = child
                    }
                    let animation = original.animation
                    guard animation.duration.isFinite, animation.duration > 0 else {
                        failure = SkeletalAssetError.missingAnimation(asset.id.rawValue)
                        return
                    }
                    animation.usesSceneTimeBase = true
                    animation.timeOffset = 0
                    animation.repeatCount = 1
                    animation.blendInDuration = 0
                    animation.blendOutDuration = 0
                    animation.isRemovedOnCompletion = false
                    let player = SCNAnimationPlayer(animation: animation)
                    player.speed = 0
                    player.blendFactor = 0
                    target.addAnimationPlayer(player, forKey: asset.id.rawValue + ":" + key)
                    player.play()
                    bindings.append(player)
                    duration = max(duration, animation.duration)
                }
            }
            attach(source.rootNode)
            source.rootNode.enumerateChildNodes { node, _ in attach(node) }
            if let failure { throw failure }
            guard !bindings.isEmpty else { throw SkeletalAssetError.missingAnimation(asset.id.rawValue) }
            clips[asset.id] = Clip(bindings: bindings, duration: duration, loops: asset.loops)
        }
    }
    private static func path(of node: SCNNode, under root: SCNNode) throws -> [String] {
        var path: [String] = []
        var owner: SCNNode? = node
        while let value = owner, value !== root {
            guard let name = value.name, !name.isEmpty,
                value.parent?.childNodes.filter({ $0.name == name }).count == 1
            else { throw SkeletalAssetError.missingTarget(L10n.text("节点名称缺失或同级名称重复")) }
            path.insert(name, at: 0)
            owner = value.parent
        }
        guard owner === root else { throw SkeletalAssetError.missingTarget(L10n.text("节点不属于资源层级")) }
        return path
    }
    @discardableResult public func advance(_ id: SceneAnimationID, deltaTime: Double) -> Bool {
        guard deltaTime.isFinite, deltaTime >= 0, clips[id] != nil else {
            lastError = L10n.text("动画输入无效或动作不存在：") + id.rawValue
            return false
        }
        let dt = min(deltaTime, 0.1)
        if current != id {
            transitionFrom = clips.mapValues(\.weight)
            transitionElapsed = current == nil ? 0.2 : 0
            if clips[id]?.weight == 0 { clips[id]?.elapsed = 0 }
            current = id
        }
        transitionElapsed = min(0.2, transitionElapsed + dt)
        let p = min(1, transitionElapsed / 0.2)
        let u = p * p * (3 - 2 * p)
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        for key in Array(clips.keys) {
            guard var clip = clips[key] else { continue }
            if key == id { clip.elapsed += dt }
            let time =
                clip.loops
                ? clip.elapsed.truncatingRemainder(dividingBy: clip.duration)
                : min(clip.elapsed, max(0, clip.duration - 0.00001))
            clip.weight = (transitionFrom[key] ?? 0) * (1 - u) + (key == id ? u : 0)
            for binding in clip.bindings {
                binding.animation.timeOffset = time
                binding.blendFactor = CGFloat(clip.weight)
            }
            clips[key] = clip
        }
        SCNTransaction.commit()
        lastError = nil
        return true
    }
    /// Diagnostic snapshot after rendering, independent of node names or a species.
    public func jointState() -> [Float] {
        joints.flatMap { node in
            let m = node.presentation.simdWorldTransform
            return [
                m.columns.0.x, m.columns.0.y, m.columns.0.z, m.columns.1.x, m.columns.1.y, m.columns.1.z,
                m.columns.2.x, m.columns.2.y, m.columns.2.z, m.columns.3.x, m.columns.3.y, m.columns.3.z,
            ]
        }
    }
}
