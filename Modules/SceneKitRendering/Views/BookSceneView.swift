import AppKit
import PopupBookCore
import SceneKit

@MainActor open class BookSceneView: SCNView {
    public let hits = HitRegistry()
    public var onInteraction: ((CharacterID, CharacterInteraction) -> Void)?
    public override var acceptsFirstResponder: Bool { true }
    public override func mouseDown(with event: NSEvent) {
        respond(at: convert(event.locationInWindow, from: nil))
    }
    @discardableResult public func respond(at point: NSPoint) -> Bool {
        for hit in hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue]) {
            if let id = hits.character(for: hit.node) {
                onInteraction?(id, .greet)
                return true
            }
        }
        return false
    }
    public func setPaused(_ paused: Bool) {
        isPlaying = !paused
        rendersContinuously = !paused
    }
    public func configure(_ stage: SceneStage) {
        scene = stage.scene
        pointOfView = stage.camera
        antialiasingMode = .multisampling4X
        preferredFramesPerSecond = 60
        autoenablesDefaultLighting = false
        allowsCameraControl = false
        setPaused(true)
    }
}
