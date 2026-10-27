import AppKit
import Foundation
import Metal
import SceneKit
import SceneKitRendering

@MainActor func run() throws {
    _ = NSApplication.shared
    let folder = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/cat-candidate")
    let names = ["CatIdle", "CatWalk", "CatSit", "CatTurn"]
    let assets = names.map {
        SceneAnimationAsset(
            id: SceneAnimationID($0), url: folder.appendingPathComponent($0 + ".usdz"), loops: $0 != "CatSit")
    }
    let model = try SkeletalModel(model: assets[0].url, animations: assets)
    let scene = SCNScene()
    scene.rootNode.addChildNode(model.root)
    let camera = SCNNode()
    camera.camera = SCNCamera()
    camera.position = SCNVector3(2, 1.5, 3)
    camera.look(at: SCNVector3(0, 0.6, 0))
    scene.rootNode.addChildNode(camera)
    let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
    renderer.scene = scene
    renderer.pointOfView = camera
    renderer.autoenablesDefaultLighting = true
    var rendererClock = 0.0
    func pose() -> [Float] {
        // The renderer clock advances even when the logical clock is frozen.
        rendererClock += 0.25
        renderer.sceneTime = rendererClock
        _ = renderer.snapshot(
            atTime: rendererClock, with: CGSize(width: 128, height: 128), antialiasingMode: .none)
        return model.jointState()
    }
    for asset in assets {
        for _ in 0..<20 { _ = model.advance(asset.id, deltaTime: 0.01) }
        let before = pose()
        for _ in 0..<30 { _ = model.advance(asset.id, deltaTime: 1.0 / 60) }
        let after = pose()
        let changed = zip(before, after).contains { abs($0 - $1) > 0.0001 }
        print("动作 \(asset.id.rawValue)：外部时钟推进骨骼=\(changed)")
        guard changed else { throw SkeletalAssetError.missingAnimation(asset.id.rawValue) }
        let frozen = pose()
        _ = model.advance(asset.id, deltaTime: 0)
        let again = pose()
        guard !zip(frozen, again).contains(where: { abs($0 - $1) > 0.0001 }) else {
            throw NSError(
                domain: "PlaybackCheck", code: 2, userInfo: [NSLocalizedDescriptionKey: "零时间步未保持姿态。"])
        }
    }
    for index in 0..<40 {
        _ = model.advance(assets[index % assets.count].id, deltaTime: 1.0 / 60)
        let before = pose()
        _ = model.advance(assets[index % assets.count].id, deltaTime: 0)
        let after = pose()
        guard !zip(before, after).contains(where: { abs($0 - $1) > 0.0001 }) else {
            throw NSError(
                domain: "PlaybackCheck", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "快速切换中的混合姿态未能冻结。"])
        }
    }
    print("四动作重用、外部时间推进、零时间步及快速切换混合冻结通过；仍非人物表演或物理用户输入验收。")
}
do { try MainActor.assumeIsolated { try run() } } catch {
    fputs("骨骼播放检查失败：\(error)\n", stderr)
    exit(1)
}
