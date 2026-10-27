import ForestCabinScene
import PopupBookCore
import SceneKit
import SceneKitRendering
import VolumeCatRendering
import XCTest

@MainActor final class SurfaceContactTests: XCTestCase {
    func testVolumePresenterRejectsMissingGroundBeforeReadingModelFiles() {
        let stage = SceneStage(
            scene: SCNScene(), camera: SCNNode(),
            anchors: [
                .entry: SCNNode(), .resting: SCNNode(), .secondaryResting: SCNNode(),
            ])
        XCTAssertThrowsError(
            try VolumeCatPresenter(stage: stage, assets: URL(fileURLWithPath: "/nonexistent"))
        ) {
            guard case VolumeCatError.missingContactSurface = $0 else { return XCTFail("应明确报告缺少落脚表面") }
        }
    }
    func testTransformedSurfaceUsesWorldCoordinates() throws {
        let scene = SCNScene()
        let parent = SCNNode()
        parent.position = SCNVector3(10, 0.3, 0)
        scene.rootNode.addChildNode(parent)
        let ground = SCNNode(geometry: SCNBox(width: 2, height: 0.2, length: 2, chamferRadius: 0))
        parent.addChildNode(ground)
        let stage = SceneStage(
            scene: scene, camera: SCNNode(), anchors: [:],
            contactSurfaces: [
                ContactSurface(node: ground, plane: .xz, size: CGSize(width: 2, height: 2), offset: 0.1)
            ])
        let hit = try XCTUnwrap(stage.contactPoint(below: SCNVector3(10, 0.5, 0)))
        XCTAssertEqual(hit.x, 10, accuracy: 0.0001)
        XCTAssertEqual(hit.y, 0.4, accuracy: 0.0001)
        XCTAssertNil(stage.contactPoint(below: SCNVector3(14, 0.5, 0)))
    }

    func testOnlyDeclaredSurfacesParticipateAndHighestStepWins() throws {
        let scene = SCNScene()
        func box(_ y: Double) -> SCNNode {
            let node = SCNNode(geometry: SCNBox(width: 2, height: 0.1, length: 2, chamferRadius: 0))
            node.position.y = CGFloat(y)
            scene.rootNode.addChildNode(node)
            return node
        }
        let page = box(0)
        let step = box(0.2)
        _ = box(0.5)  // An actor or decoration must not become a floor.
        let stage = SceneStage(
            scene: scene, camera: SCNNode(), anchors: [:],
            contactSurfaces: [page, step].map {
                ContactSurface(node: $0, plane: .xz, size: CGSize(width: 2, height: 2), offset: 0.05)
            })
        XCTAssertEqual(
            try XCTUnwrap(stage.contactPoint(below: SCNVector3(0, 0.5, 0))).y, 0.25, accuracy: 0.0001)
        step.isHidden = true
        XCTAssertEqual(
            try XCTUnwrap(stage.contactPoint(below: SCNVector3(0, 0.5, 0))).y, 0.05, accuracy: 0.0001)
    }

    func testForestProvidesContactWithoutChangingLegacyAnchorHeight() throws {
        let stage = ForestCabin().stage
        for id in [AnchorID.entry, .resting, .secondaryResting] {
            let anchor = try stage.anchor(id)
            XCTAssertEqual(anchor.worldPosition.y, 0.14, accuracy: 0.0001)
            let contact = try XCTUnwrap(stage.contactPoint(below: anchor.worldPosition))
            XCTAssertEqual(contact.y, 0.055, accuracy: 0.0001)
        }
        XCTAssertNil(stage.contactPoint(below: SCNVector3(.nan, 0.14, 0)))
    }

    func testRotatedEllipseOnlyCoversItsActualFootprint() throws {
        let scene = SCNScene()
        let surface = SCNNode()
        surface.eulerAngles.x = -.pi / 2
        surface.position.y = 0.09
        scene.rootNode.addChildNode(surface)
        let stage = SceneStage(
            scene: scene, camera: SCNNode(), anchors: [:],
            contactSurfaces: [
                ContactSurface(
                    node: surface, plane: .xy, size: CGSize(width: 2, height: 1), offset: 0.02,
                    footprint: .ellipse)
            ])
        XCTAssertEqual(
            try XCTUnwrap(stage.contactPoint(below: SCNVector3(0, 0.3, 0))).y, 0.11, accuracy: 0.0001)
        XCTAssertNil(stage.contactPoint(below: SCNVector3(0.9, 0.3, 0.45)), "不能把椭圆包围盒的角当作落脚表面")
    }

    func testPlacementCrossesSeamsContinuouslyAndFreezesWhenPaused() {
        let scene = SCNScene()
        let surface = SCNNode()
        scene.rootNode.addChildNode(surface)
        let stage = SceneStage(
            scene: scene, camera: SCNNode(), anchors: [:],
            contactSurfaces: [
                ContactSurface(node: surface, plane: .xz, size: CGSize(width: 2, height: 2), offset: 0.05)
            ])
        var placement = SurfacePlacement()
        let position = SCNVector3(0, 0.14, 0)
        XCTAssertEqual(placement.update(at: position, in: stage, deltaTime: 0.02), 0.05, accuracy: 0.0001)
        let seam = SCNVector3(3, 0.14, 0)
        XCTAssertEqual(placement.update(at: seam, in: stage, deltaTime: 0.02), 0.05, accuracy: 0.0001)
        surface.position.y = 0.1
        XCTAssertEqual(placement.update(at: position, in: stage, deltaTime: 0), 0.05, accuracy: 0.0001)
        XCTAssertEqual(placement.update(at: position, in: stage, deltaTime: .nan), 0.05, accuracy: 0.0001)
        let moving = placement.update(at: position, in: stage, deltaTime: 1.0 / 60)
        XCTAssertGreaterThan(moving, 0.05)
        XCTAssertLessThan(moving, 0.15)
        for _ in 0..<120 { _ = placement.update(at: position, in: stage, deltaTime: 1.0 / 60) }
        XCTAssertEqual(placement.height ?? 0, 0.15, accuracy: 0.0001)
    }
}
