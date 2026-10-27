import AppKit
import Foundation
import RealityKit

struct ImportedClip: Codable {
    let file: String
    let entities: Int
    let models: Int
    let materials: Int
    let joints: Int
    let animationReferences: Int
    let invalidJointModels: Int
    let durations: [Double]
}
struct ImportComparison: Codable {
    let scope: String
    let operatingSystem: String
    let files: [ImportedClip]
    let structurePassed: Bool
    let productionMigrationApproved: Bool
}

@MainActor func run() throws {
    _ = NSApplication.shared
    let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/cat-candidate")
    var results: [ImportedClip] = []
    for name in ["CatIdle", "CatWalk", "CatSit", "CatTurn"] {
        let root = try Entity.load(contentsOf: directory.appendingPathComponent(name + ".usdz"))
        var entities = 0
        var models = 0
        var materials = 0
        var joints = 0
        var animations = 0
        var invalidJointModels = 0
        var durations: [Double] = []
        @MainActor func inspect(_ entity: Entity) {
            entities += 1
            if let model = entity as? ModelEntity, let geometry = model.model {
                models += 1
                materials += geometry.materials.count
                joints += model.jointNames.count
                if model.jointNames.count != model.jointTransforms.count { invalidJointModels += 1 }
            }
            for animation in entity.availableAnimations {
                animations += 1
                let playback = entity.playAnimation(animation, startsPaused: true)
                durations.append(playback.duration)
                playback.stop()
            }
            for child in entity.children { inspect(child) }
        }
        inspect(root)
        guard models > 0, materials > 0, joints > 0, animations > 0, invalidJointModels == 0,
            durations.allSatisfy({ $0.isFinite && $0 > 0 })
        else {
            throw NSError(
                domain: "RealityAssetCheck", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "RealityKit导入缺少模型、骨骼或有效片段：" + name])
        }
        results.append(
            ImportedClip(
                file: name + ".usdz", entities: entities, models: models, materials: materials,
                joints: joints, animationReferences: animations, invalidJointModels: invalidJointModels,
                durations: durations))
    }
    let report = ImportComparison(
        scope: "仅同一USDZ的结构导入；动画引用按实体递归计数；未验证骨骼实际播放、画面、折叠、命中、声音和性能",
        operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString, files: results,
        structurePassed: true, productionMigrationApproved: false)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(report), as: UTF8.self))
}
do { try MainActor.assumeIsolated { try run() } } catch {
    fputs("RealityKit候选结构检查失败：\(error)\n", stderr)
    exit(1)
}
