import AppKit
import SceneKit

/// Fit declared content points to a viewport without including oversized background geometry.
@MainActor public enum SceneFraming {
    public static func fit(_ points: [SCNVector3], camera node: SCNNode, viewport: CGSize) {
        guard let camera = node.camera, !points.isEmpty,
            viewport.width > 0, viewport.height > 0
        else { return }
        let local = points.map { node.convertPosition($0, from: nil) }
        guard let minX = local.map(\.x).min(), let maxX = local.map(\.x).max(),
            let minY = local.map(\.y).min(), let maxY = local.map(\.y).max()
        else { return }
        SCNTransaction.begin()
        SCNTransaction.disableActions = true
        node.localTranslate(by: SCNVector3((minX + maxX) / 2, (minY + maxY) / 2, 0))
        camera.usesOrthographicProjection = true
        camera.projectionDirection = .vertical
        camera.orthographicScale = 1
        let unit = camera.projectionTransform(withViewportSize: viewport)
        let width = (maxX - minX) / 2 * abs(unit.m11)
        let height = (maxY - minY) / 2 * abs(unit.m22)
        camera.orthographicScale = Double(max(0.1, max(width, height))) * 1.055
        SCNTransaction.commit()
    }
}
