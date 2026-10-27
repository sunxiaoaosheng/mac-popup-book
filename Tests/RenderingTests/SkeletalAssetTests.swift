import Foundation
import QuartzCore
import SceneKit
import SceneKitRendering
import XCTest

@MainActor final class SkeletalAssetTests: XCTestCase {
    func testInvalidConfigurationIsRejectedBeforeOpeningFiles() {
        let missing = URL(fileURLWithPath: "/nonexistent/model.scn")
        let duplicate = SceneAnimationAsset(id: SceneAnimationID("walk"), url: missing, loops: true)
        let blank = SceneAnimationAsset(id: SceneAnimationID("  "), url: missing, loops: false)
        for assets in [[], [duplicate, duplicate], [blank]] {
            XCTAssertThrowsError(try SkeletalModel(model: missing, animations: assets)) { error in
                guard case SkeletalAssetError.invalidConfiguration = error else {
                    return XCTFail("应报告配置错误，而不是读取文件：\(error)")
                }
            }
        }
    }

    func testDifferentSkeletonIsRejectedEvenWhenAnimatedOwnerMatches() throws {
        try withDirectory { directory in
            let model = try fixture(directory, name: "model", joint: "joint-a")
            let clip = try fixture(directory, name: "clip", joint: "joint-b")
            XCTAssertThrowsError(
                try SkeletalModel(
                    model: model,
                    animations: [.init(id: .init("walk"), url: clip, loops: true)])
            ) { error in
                guard case SkeletalAssetError.incompatibleSkeleton("walk") = error else {
                    return XCTFail("骨骼不匹配必须显式失败：\(error)")
                }
            }
        }
    }

    func testMatchingSkeletonLoadsAndInvalidAdvanceReportsErrorThenRecovers() throws {
        try withDirectory { directory in
            let modelURL = try fixture(directory, name: "model", joint: "joint")
            let clip = try fixture(directory, name: "clip", joint: "joint")
            let id = SceneAnimationID("walk")
            let model = try SkeletalModel(
                model: modelURL, animations: [.init(id: id, url: clip, loops: true)])
            XCTAssertTrue(model.advance(id, deltaTime: 0.02))
            XCTAssertFalse(model.advance(id, deltaTime: .nan))
            XCTAssertNotNil(model.lastError)
            XCTAssertFalse(model.advance(.init("missing"), deltaTime: 0.02))
            XCTAssertTrue(model.advance(id, deltaTime: 0))
            XCTAssertNil(model.lastError)
        }
    }

    func testAmbiguousSiblingNamesDoNotSilentlySelectFirstTarget() throws {
        try withDirectory { directory in
            let model = try fixture(directory, name: "model", joint: "joint", duplicate: true)
            let clip = try fixture(directory, name: "clip", joint: "joint")
            XCTAssertThrowsError(
                try SkeletalModel(
                    model: model,
                    animations: [.init(id: .init("walk"), url: clip, loops: true)])
            ) { error in
                guard case SkeletalAssetError.missingTarget = error else {
                    return XCTFail("同级重名必须报告目标歧义：\(error)")
                }
            }
        }
    }

    func testRapidReversalKeepsBlendNormalizedAndZeroTimeFreezesTransition() throws {
        try withDirectory { directory in
            let source = try fixture(directory, name: "character", joint: "joint")
            let ids = [SceneAnimationID("idle"), .init("walk"), .init("sit")]
            let model = try SkeletalModel(
                model: source,
                animations: ids.map { .init(id: $0, url: source, loops: true) })
            @MainActor func weights() -> [Double] {
                var result: [String: Double] = [:]
                model.root.enumerateChildNodes { node, _ in
                    for key in node.animationKeys {
                        result[key] = Double(node.animationPlayer(forKey: key)!.blendFactor)
                    }
                }
                return result.sorted { $0.key < $1.key }.map(\.value)
            }
            XCTAssertTrue(model.advance(ids[0], deltaTime: 0.01))
            for index in 0..<120 {
                let id = ids[index % ids.count]
                XCTAssertTrue(model.advance(id, deltaTime: 1.0 / 60))
                let before = weights()
                XCTAssertEqual(before.count, ids.count)
                XCTAssertEqual(before.reduce(0, +), 1, accuracy: 0.00001)
                XCTAssertTrue(before.allSatisfy { $0.isFinite && (0...1).contains($0) })
                XCTAssertTrue(model.advance(id, deltaTime: 0))
                XCTAssertEqual(weights(), before, "暂停时混合权重也必须保持")
            }
            for _ in 0..<30 { _ = model.advance(ids[0], deltaTime: 1.0 / 60) }
            let settled = weights()
            XCTAssertEqual(settled.filter { $0 > 0.00001 }.count, 1, "反向不能留下旧动作叠加")
            XCTAssertFalse(model.advance(.init("missing"), deltaTime: 0.1))
            XCTAssertEqual(weights(), settled)
        }
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private func fixture(_ directory: URL, name: String, joint: String, duplicate: Bool = false) throws
        -> URL
    {
        let scene = SCNScene()
        let rig = SCNNode()
        rig.name = "rig"
        scene.rootNode.addChildNode(rig)
        let bone = SCNNode()
        bone.name = joint
        rig.addChildNode(bone)
        if duplicate {
            let other = SCNNode()
            other.name = joint
            rig.addChildNode(other)
        }
        let vertices = [SCNVector3(0, 0, 0), SCNVector3(1, 0, 0), SCNVector3(0, 1, 0)]
        let element = SCNGeometryElement(indices: [Int32(0), 1, 2], primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)], elements: [element])
        let weights: [Float] = [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0]
        let indices = [UInt16](repeating: 0, count: 12)
        let weightData = weights.withUnsafeBytes { Data($0) }
        let indexData = indices.withUnsafeBytes { Data($0) }
        let weightSource = SCNGeometrySource(
            data: weightData, semantic: .boneWeights, vectorCount: 3, usesFloatComponents: true,
            componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
        let indexSource = SCNGeometrySource(
            data: indexData, semantic: .boneIndices, vectorCount: 3, usesFloatComponents: false,
            componentsPerVector: 4, bytesPerComponent: 2, dataOffset: 0, dataStride: 8)
        let mesh = SCNNode(geometry: geometry)
        mesh.name = "mesh"
        mesh.skinner = SCNSkinner(
            baseGeometry: geometry, bones: [bone],
            boneInverseBindTransforms: [NSValue(scnMatrix4: SCNMatrix4Identity)],
            boneWeights: weightSource, boneIndices: indexSource)
        mesh.skinner?.skeleton = rig
        scene.rootNode.addChildNode(mesh)
        let animation = CABasicAnimation(keyPath: "eulerAngles.x")
        animation.fromValue = 0
        animation.toValue = 0.2
        animation.duration = 1
        rig.addAnimation(animation, forKey: "motion")
        let url = directory.appendingPathComponent(name + ".scn")
        guard scene.write(to: url, options: nil, delegate: nil, progressHandler: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }
}
