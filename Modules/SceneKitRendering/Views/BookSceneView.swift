import AppKit
import PopupBookCore
import SceneKit

@MainActor open class BookSceneView: SCNView {
    public let hits = HitRegistry()
    public var onInteraction: ((CharacterID, CharacterInteraction) -> Void)?
    private var stage: SceneStage?
    open override func layout() {
        super.layout()
        stage?.fit(viewport: bounds.size)
    }
    private var gesture = ContactGesture()
    private var contactID: CharacterID?
    private var tracking: NSTrackingArea?
    private var hoverTimer: Timer?
    private var hoverID: CharacterID?
    private var pendingInvitation: (point: NSPoint, time: Double)?
    private var invitation: (SCNNode, AnchorID, CharacterID)?
    public override var acceptsFirstResponder: Bool { true }
    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { window.acceptsMouseMovedEvents = true } else { cancelInteractions() }
    }
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [
                .mouseMoved, .mouseEnteredAndExited,
                .activeInKeyWindow, .inVisibleRect, .enabledDuringMouseDrag,
            ], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    public func registerInvitation(_ node: SCNNode, anchor: AnchorID, for id: CharacterID) {
        invitation = (node, anchor, id)
    }
    public override func mouseDown(with event: NSEvent) {
        guard isPlaying else { return }
        window?.makeFirstResponder(self)
        cancelHover()
        let point = convert(event.locationInWindow, from: nil)
        guard let (id, local) = hitContact(at: point) else {
            if let (node, _, _) = invitation {
                let projected = projectPoint(node.worldPosition)
                if hypot(point.x - projected.x, point.y - projected.y) < 30 {
                    pendingInvitation = (point, event.timestamp)
                }
            }
            return
        }
        contactID = id
        emit(
            gesture.begin(
                x: point.x, y: point.y, time: event.timestamp,
                point: local), to: id)
    }
    public override func mouseDragged(with event: NSEvent) {
        guard let id = contactID else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard isPlaying, let (hitID, local) = hitContact(at: point), hitID == id
        else {
            cancelInteractions()
            return
        }
        emit(
            gesture.move(
                x: point.x, y: point.y, time: event.timestamp,
                point: local), to: id)
    }
    public override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let id = contactID {
            // Account for a final displacement even when AppKit coalesces drag events.
            if let (hitID, local) = hitContact(at: point), hitID == id {
                emit(gesture.move(x: point.x, y: point.y, time: event.timestamp, point: local), to: id)
                emit(gesture.end(time: event.timestamp), to: id)
            } else {
                emit(gesture.cancel(), to: id)
            }
            contactID = nil
        } else if isPlaying, let pending = pendingInvitation, event.timestamp - pending.time <= 0.3,
            hypot(point.x - pending.point.x, point.y - pending.point.y) <= 6,
            let (node, anchor, id) = invitation
        {
            let projected = projectPoint(node.worldPosition)
            if hypot(point.x - projected.x, point.y - projected.y) < 30 {
                onInteraction?(id, .invite(anchor))
            }
        }
        pendingInvitation = nil
    }
    public override func mouseMoved(with event: NSEvent) {
        guard isPlaying, contactID == nil else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard
            let (id, rect) = hits.roots.compactMap({ _, id -> (CharacterID, NSRect)? in
                guard let rect = projectedBounds(for: id), rect.insetBy(dx: -40, dy: -40).contains(point)
                else { return nil }
                return (id, rect)
            }).first
        else {
            cancelHover()
            return
        }
        if hoverID != id { cancelHover() }
        guard hoverTimer == nil else { return }
        hoverID = id
        let local = normalized(point, in: rect)
        let timer = Timer(timeInterval: 0.15, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying, self.hoverID == id else { return }
                self.onInteraction?(id, .attention(local))
                self.hoverTimer = nil
            }
        }
        hoverTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    public override func mouseExited(with event: NSEvent) { cancelInteractions() }
    public override func cancelOperation(_ sender: Any?) { cancelInteractions() }
    public func cancelInteractions() {
        if let id = contactID { emit(gesture.cancel(), to: id) }
        contactID = nil
        pendingInvitation = nil
        cancelHover()
    }
    private func cancelHover() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        hoverID = nil
    }
    private func emit(_ interactions: [CharacterInteraction], to id: CharacterID) {
        for interaction in interactions { onInteraction?(id, interaction) }
    }
    private func hitCharacter(at point: NSPoint) -> CharacterID? { hitContact(at: point)?.0 }
    private func hitContact(at point: NSPoint) -> (CharacterID, ContactPoint)? {
        guard let hit = hitTest(point, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue]).first,
            let (root, id) = hits.root(for: hit.node)
        else { return nil }
        let position = root.convertPosition(hit.worldCoordinates, from: nil)
        let box = root.boundingBox
        return (
            id,
            ContactPoint(
                x: Double((position.x - box.min.x) / max(0.001, box.max.x - box.min.x)),
                y: Double((position.y - box.min.y) / max(0.001, box.max.y - box.min.y)))
        )
    }
    private func projectedBounds(for id: CharacterID) -> NSRect? {
        for (node, identity) in hits.roots where identity == id && !node.isHidden && node.opacity > 0.05 {
            let box = node.boundingBox
            var points: [SCNVector3] = []
            for x in [box.min.x, box.max.x] {
                for y in [box.min.y, box.max.y] {
                    for z in [box.min.z, box.max.z] {
                        points.append(projectPoint(node.convertPosition(SCNVector3(x, y, z), to: nil)))
                    }
                }
            }
            guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
                let minY = points.map(\.y).min(), let maxY = points.map(\.y).max(),
                minX.isFinite, maxX.isFinite, minY.isFinite, maxY.isFinite
            else { continue }
            return NSRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
        }
        return nil
    }
    private func normalized(_ point: NSPoint, in rect: NSRect) -> ContactPoint {
        ContactPoint(x: (point.x - rect.minX) / rect.width, y: (point.y - rect.minY) / rect.height)
    }
    /// Explicit semantic hit used by the integration harness, separate from physical pointer checks.
    @discardableResult public func respond(at point: NSPoint) -> Bool {
        guard let id = hitCharacter(at: point) else { return false }
        onInteraction?(id, .greet)
        return true
    }
    public func setPaused(_ paused: Bool) {
        if paused { cancelInteractions() }
        isPlaying = !paused
        rendersContinuously = !paused
    }
    public func configure(_ stage: SceneStage) {
        self.stage = stage
        scene = stage.scene
        pointOfView = stage.camera
        antialiasingMode = .multisampling4X
        preferredFramesPerSecond = 60
        autoenablesDefaultLighting = false
        allowsCameraControl = false
        stage.fit(viewport: bounds.size)
        setPaused(true)
    }
    deinit { hoverTimer?.invalidate() }
}
