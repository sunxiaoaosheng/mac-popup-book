import SwiftUI
import SceneKit

final class PaperView: SCNView {
    var onCat: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        respondToCat(at: convert(event.locationInWindow,from:nil))
    }
    func respondToCat(at p: NSPoint) {
        for result in hitTest(p,options:[.searchMode:SCNHitTestSearchMode.all.rawValue]) {
            var n: SCNNode? = result.node
            while let current = n {
                if current.name == "cat" { onCat?(); return }; n = current.parent
            }
        }
    }
    override var acceptsFirstResponder: Bool { true }
}
struct ForestSceneView: NSViewRepresentable {
    let model: BookModel
    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        weak var model: BookModel?
        func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) { model?.renderFrame(at:time) }
    }
    func makeCoordinator() -> Coordinator { let c = Coordinator(); c.model = model; return c }
    func makeNSView(context: Context) -> PaperView {
        let v = PaperView(frame:.zero,options:[SCNView.Option.preferredRenderingAPI.rawValue:SCNRenderingAPI.metal.rawValue])
        v.scene = model.world.scene; v.pointOfView = model.world.camera
        v.antialiasingMode = .multisampling4X; v.preferredFramesPerSecond = 60
        v.autoenablesDefaultLighting = false; v.allowsCameraControl = false
        v.isPlaying = true; v.rendersContinuously = true; v.delegate = context.coordinator
        v.onCat = { [weak model] in model?.greet() }
        v.setAccessibilityElement(true)
        v.setAccessibilityRole(.image)
        v.setAccessibilityLabel("纸雕森林")
        model.updateAccessibility = { [weak v] label in v?.setAccessibilityLabel(label) }
        model.pauseRendering = { [weak v] paused in v?.isPlaying = !paused; v?.rendersContinuously = !paused }
        return v
    }
    func updateNSView(_ view: PaperView,context: Context) { }
}
