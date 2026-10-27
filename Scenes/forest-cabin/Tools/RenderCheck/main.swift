import AppKit
import ForestCabinScene
import Metal
import PaperCatBehavior
import PaperCatRendering
import PopupBookCore
import SceneKit
import SceneKitRendering

@MainActor func run() throws {
    _ = NSApplication.shared
    let world = ForestCabin()
    let cat = PaperCat()
    let actor = try PaperCatPresenter(stage: world.stage)
    let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
    renderer.scene = world.scene
    renderer.pointOfView = world.camera
    world.stage.fit(viewport: CGSize(width: 1600, height: 1100))
    let path = CommandLine.arguments.dropFirst().first ?? "build/checks/render"
    let directory = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for (name, p) in [
        ("open", 1.0), ("attention", 1.0), ("petting", 1.0), ("invited", 1.0), ("half", 0.5),
        ("closed", 0.03),
    ] {
        let context = WorldContext(progress: p, clock: p > 0.8 ? 5 : 0, deltaTime: 0, stableDuration: 0)
        var pose = cat.pose
        if p > 0.8 {
            pose.outside = 1
            pose.mood = .resting
        }
        if name == "attention" {
            pose.attention = 1
            pose.gaze = ContactPoint(x: 0.95, y: 0.7)
            pose.acknowledgement = 1
        }
        if name == "petting" {
            pose.mood = .petting
            pose.touchBlend = 1
            pose.blink = 0.88
        }
        if name == "invited" {
            pose.mood = .strolling
            pose.roaming = 1
            pose.acknowledgement = 1
        }
        world.update(in: context, events: p < 0.65 ? [.returningInside] : [])
        actor.update(pose, in: context)
        let image = renderer.snapshot(
            atTime: 0, with: CGSize(width: 1600, height: 1100), antialiasingMode: .multisampling4X)
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: directory.appendingPathComponent(name + ".png"))
        print("已渲染：\(name)")
    }
}
do { try MainActor.assumeIsolated { try run() } } catch {
    fputs("渲染检查失败：\(error)\n", stderr)
    exit(1)
}
