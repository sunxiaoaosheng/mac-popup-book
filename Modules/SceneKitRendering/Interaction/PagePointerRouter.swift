import Foundation
import PopupBookCore
import SceneKit

/// Projects renderer-local inputs without creating a window or accessing global pointer state.
@MainActor public final class PagePointerRouter {
    public let hits = HitRegistry()
    public var onInteraction: ((CharacterID, CharacterInteraction) -> Void)?
    public var viewport = CGSize(width: 1, height: 1)
    private let renderer: any SCNSceneRenderer
    private var gesture = ContactGesture()
    private var contact: CharacterID?
    private var lastAttention = -1.0
    private var invitation: (SCNNode, AnchorID, CharacterID)?
    private var pending: (CGPoint, Double)?
    public init(renderer: any SCNSceneRenderer) { self.renderer = renderer }
    public func registerInvitation(_ node: SCNNode, anchor: AnchorID, for id: CharacterID) {
        invitation = (node, anchor, id)
    }
    public func cancel() {
        if let contact { emit(gesture.cancel(), to: contact) }
        contact = nil
        pending = nil
    }
    public func handle(_ event: PagePointer) {
        let point = CGPoint(x: event.x * viewport.width, y: event.y * viewport.height)
        switch event.kind {
        case .cancel: cancel()
        case .down:
            cancel()
            if let (id, local) = hit(point) {
                contact = id
                emit(gesture.begin(x: point.x, y: point.y, time: event.time, point: local), to: id)
            } else {
                pending = (point, event.time)
            }
        case .drag:
            guard let contact else { return }
            guard let (id, local) = hit(point), id == contact else {
                cancel()
                return
            }
            emit(gesture.move(x: point.x, y: point.y, time: event.time, point: local), to: id)
        case .up:
            if let id = contact {
                if let (hitID, local) = hit(point), hitID == id {
                    emit(gesture.move(x: point.x, y: point.y, time: event.time, point: local), to: id)
                    emit(gesture.end(time: event.time), to: id)
                } else {
                    emit(gesture.cancel(), to: id)
                }
            } else if let pending, event.time - pending.1 < 0.3,
                hypot(point.x - pending.0.x, point.y - pending.0.y) < 6, let (node, anchor, id) = invitation
            {
                let p = renderer.projectPoint(node.worldPosition)
                if hypot(point.x - CGFloat(p.x), point.y - CGFloat(p.y)) < 30 {
                    onInteraction?(id, .invite(anchor))
                }
            }
            contact = nil
            pending = nil
        case .move:
            guard contact == nil, event.time - lastAttention >= 0.15 else { return }
            for (node, id) in hits.roots where !node.isHidden && node.opacity > 0.05 {
                let b = node.boundingBox
                var points: [SCNVector3] = []
                for x in [b.min.x, b.max.x] {
                    for y in [b.min.y, b.max.y] {
                        for z in [b.min.z, b.max.z] {
                            points.append(
                                renderer.projectPoint(node.convertPosition(SCNVector3(x, y, z), to: nil)))
                        }
                    }
                }
                guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
                    let minY = points.map(\.y).min(), let maxY = points.map(\.y).max()
                else { continue }
                let rect = CGRect(
                    x: CGFloat(minX), y: CGFloat(minY), width: CGFloat(maxX - minX),
                    height: CGFloat(maxY - minY))
                if rect.insetBy(dx: -40, dy: -40).contains(point) {
                    lastAttention = event.time
                    onInteraction?(
                        id,
                        .attention(
                            ContactPoint(
                                x: (point.x - rect.minX) / max(1, rect.width),
                                y: (point.y - rect.minY) / max(1, rect.height))))
                    break
                }
            }
        }
    }
    private func hit(_ point: CGPoint) -> (CharacterID, ContactPoint)? {
        guard
            let result = renderer.hitTest(
                point, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue]
            ).first, let (root, id) = hits.root(for: result.node)
        else { return nil }
        let position = root.convertPosition(result.worldCoordinates, from: nil)
        let box = root.boundingBox
        return (
            id,
            ContactPoint(
                x: Double((position.x - box.min.x) / max(0.001, box.max.x - box.min.x)),
                y: Double((position.y - box.min.y) / max(0.001, box.max.y - box.min.y)))
        )
    }
    private func emit(_ values: [CharacterInteraction], to id: CharacterID) {
        for value in values { onInteraction?(id, value) }
    }
}
