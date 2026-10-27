import AppKit
import ForestCabinScene
import Foundation
import Metal
import PaperCatBehavior
import PopupBookCore
import SceneKit
import VolumeCatRendering

@MainActor func run() throws {
    _ = NSApplication.shared
    let assets = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/cat-candidate")
    let output = assets.appendingPathComponent("book-preview")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let world = ForestCabin()
    let presenter = try VolumeCatPresenter(stage: world.stage, assets: assets)
    let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
    renderer.scene = world.scene
    renderer.pointOfView = world.camera
    for (name, progress, outside, mood) in [
        ("open", 1.0, 1.0, CatMood.resting),
        ("half-return", 0.5, 0.7, CatMood.returning), ("closed", 0.03, 0.0, CatMood.sleeping),
    ] {
        var pose = CatPose()
        pose.outside = outside
        pose.mood = mood
        pose.facing = mood == .returning ? .pi : 0
        for frame in 0..<60 {
            let context = WorldContext(
                progress: progress, clock: Double(frame) / 60, deltaTime: 1.0 / 60, stableDuration: 1)
            world.update(in: context, events: mood == .returning ? [.returningInside] : [])
            presenter.update(pose, in: context)
        }
        guard presenter.lastError == nil else {
            throw NSError(
                domain: "CandidateSceneCheck", code: 1,
                userInfo: [NSLocalizedDescriptionKey: presenter.lastError!])
        }
        let image = renderer.snapshot(
            atTime: 0, with: CGSize(width: 1600, height: 1100), antialiasingMode: .multisampling4X)
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: output.appendingPathComponent(name + ".png"))
        print("已输出候选 \(name)；完整角色演出仍待验收。")
    }
}
do { try MainActor.assumeIsolated { try run() } } catch {
    fputs("候选场景检查失败：\(error)\n", stderr)
    exit(1)
}
