import SceneKit
import SceneKitRendering
import XCTest

@MainActor final class FramingTests: XCTestCase {
    func testContentFillsViewportWithoutClippingAcrossAspectRatios() {
        let node = SCNNode()
        node.camera = SCNCamera()
        node.position = SCNVector3(5.6, 8.8, 16.5)
        node.look(at: SCNVector3(0, 0.7, 0))
        let points = [
            SCNVector3(-5.4, 0, -3.5), SCNVector3(5.4, 0, -3.5),
            SCNVector3(-5.4, 0, 3.5), SCNVector3(5.4, 0, 3.5), SCNVector3(-3.6, 4, -1.7),
        ]
        for size in [
            CGSize(width: 880, height: 680), CGSize(width: 1920, height: 1080),
            CGSize(width: 900, height: 1400),
        ] {
            SceneFraming.fit(points, camera: node, viewport: size)
            let matrix = node.camera!.projectionTransform(withViewportSize: size)
            let extents = points.flatMap { point -> [CGFloat] in
                let local = node.convertPosition(point, from: nil)
                return [abs(local.x * matrix.m11), abs(local.y * matrix.m22)]
            }
            XCTAssertLessThanOrEqual(extents.max() ?? 2, 0.96, "场景边缘不能被裁掉")
            XCTAssertGreaterThan(extents.max() ?? 0, 0.93, "至少一边应接近满幅")
            let previous = node.worldPosition
            SceneFraming.fit(points, camera: node, viewport: size)
            XCTAssertEqual(node.worldPosition.x, previous.x, accuracy: 0.0001)
            XCTAssertEqual(node.worldPosition.y, previous.y, accuracy: 0.0001)
        }
    }
}
