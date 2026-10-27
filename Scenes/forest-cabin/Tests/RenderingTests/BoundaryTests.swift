import ForestCabinScene
import PaperCatBehavior
import PaperCatRendering
import PopupBookCore
import SceneKit
import SceneKitRendering
import XCTest

@MainActor final class BoundaryTests: XCTestCase {
    func testEnvironmentDoesNotCreateCharacterAndIdentityIsNotNodeName() throws {
        let world = ForestCabin()
        XCTAssertNil(world.scene.rootNode.childNode(withName: "cat", recursively: true))
        let presenter = try PaperCatPresenter(stage: world.stage)
        let hits = HitRegistry()
        let id = CharacterID("replaceable-resident")
        hits.register(presenter.cat, as: id)
        let child = SCNNode()
        presenter.cat.addChildNode(child)
        child.name = "arbitrary-shape"
        XCTAssertEqual(hits.character(for: child), id)
        hits.unregister(presenter.cat)
        XCTAssertNil(hits.character(for: child))
    }
    func testMissingRenderAnchorIsExplicitError() {
        let stage = SceneStage(scene: SCNScene(), camera: SCNNode(), anchors: [:])
        XCTAssertThrowsError(try PaperCatPresenter(stage: stage))
    }
}
