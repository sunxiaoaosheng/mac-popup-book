import AppKit
import Foundation
import Metal
import SceneKit

struct ImportReport: Codable {
    let file: String
    let nodes: Int
    let geometries: Int
    let skinners: Int
    let bones: Int
    let weightedVertices: Int
    let invalidWeightVertices: Int
    let animationKeys: [String]
    let posedMatricesDifferent: Bool?
    let passed: Bool
}

do {
    guard let argument = CommandLine.arguments.dropFirst().first else {
        throw NSError(domain: "AssetCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "请提供待检查的三维资产路径。"])
    }
    let url = URL(fileURLWithPath: argument)
    let scene = try SCNScene(url: url, options: [.checkConsistency: true])
    var nodes = 1
    var geometries = 0
    var skinners = 0
    var bones = 0
    var weightedVertices = 0
    var invalidWeightVertices = 0
    var animationKeys = scene.rootNode.animationKeys
    scene.rootNode.enumerateChildNodes { node, _ in
        nodes += 1
        if node.geometry != nil { geometries += 1 }
        if let skin = node.skinner {
            skinners += 1
            bones += skin.bones.count
            let audit = SkinWeightAudit(skin)
            weightedVertices += audit.vertices
            invalidWeightVertices += audit.invalidVertices
        }
        animationKeys += node.animationKeys
    }
    var posedMatricesDifferent: Bool?
    if let output = CommandLine.arguments.dropFirst(2).first {
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        scene.background.contents = NSColor(calibratedWhite: 0.98, alpha: 1)
        let box = scene.rootNode.boundingBox
        let center = SCNVector3(
            (box.min.x + box.max.x) / 2, (box.min.y + box.max.y) / 2, (box.min.z + box.max.z) / 2)
        let size = max(0.1, max(box.max.x - box.min.x, max(box.max.y - box.min.y, box.max.z - box.min.z)))
        camera.camera?.orthographicScale = Double(size) * 0.7
        camera.position = SCNVector3(center.x + size * 1.4, center.y + size * 0.8, center.z + size * 2.4)
        camera.look(at: center)
        scene.rootNode.addChildNode(camera)
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        renderer.autoenablesDefaultLighting = true
        var jointNodes: [SCNNode] = []
        scene.rootNode.enumerateChildNodes { node, _ in
            if let skinner = node.skinner { jointNodes += skinner.bones }
            for key in node.animationKeys {
                node.animationPlayer(forKey: key)?.animation.usesSceneTimeBase = true
            }
        }
        func matrices() -> [Float] {
            jointNodes.flatMap { node -> [Float] in
                let m = node.presentation.simdWorldTransform
                return [
                    m.columns.0.x, m.columns.0.y, m.columns.0.z, m.columns.1.x, m.columns.1.y, m.columns.1.z,
                    m.columns.2.x, m.columns.2.y, m.columns.2.z, m.columns.3.x, m.columns.3.y, m.columns.3.z,
                ]
            }
        }
        var firstPose: [Float] = []
        for (name, time) in [("start", 0.0), ("sway", 0.5)] {
            renderer.sceneTime = time
            let image = renderer.snapshot(
                atTime: time, with: CGSize(width: 640, height: 640), antialiasingMode: .multisampling4X)
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                let png = bitmap.representation(using: .png, properties: [:])
            else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: directory.appendingPathComponent(name + ".png"))
            let pose = matrices()
            if firstPose.isEmpty {
                firstPose = pose
            } else {
                posedMatricesDifferent = zip(firstPose, pose).contains { abs($0 - $1) > 0.0001 }
            }
        }
    }
    let report = ImportReport(
        file: url.lastPathComponent, nodes: nodes, geometries: geometries,
        skinners: skinners, bones: bones, weightedVertices: weightedVertices,
        invalidWeightVertices: invalidWeightVertices, animationKeys: animationKeys,
        posedMatricesDifferent: posedMatricesDifferent,
        passed: geometries > 0 && skinners > 0 && weightedVertices > 0 && invalidWeightVertices == 0
            && !animationKeys.isEmpty && posedMatricesDifferent != false)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(report), as: UTF8.self))
    if !report.passed {
        fputs("资产未通过SceneKit骨骼/动画完整性预检；不能只凭模型可见视作导入成功。\n", stderr)
        exit(2)
    }
} catch {
    fputs("资产导入失败：\(error)\n", stderr)
    exit(1)
}
