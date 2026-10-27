import Foundation
import SceneKit

struct SkinWeightAudit {
    let vertices: Int
    let invalidVertices: Int
    init(_ skin: SCNSkinner) {
        let weights = skin.boneWeights
        let indices = skin.boneIndices
        vertices = weights.vectorCount
        var invalid = 0
        for vertex in 0..<weights.vectorCount {
            var sum = 0.0
            var valid =
                weights.componentsPerVector == indices.componentsPerVector
                && indices.vectorCount == weights.vectorCount
            for component in 0..<weights.componentsPerVector {
                guard let weight = Self.value(weights, vector: vertex, component: component),
                    let index = Self.value(indices, vector: vertex, component: component),
                    weight.isFinite, weight >= 0, index.isFinite, index >= 0
                else {
                    valid = false
                    continue
                }
                if weight > 0 && (index >= Double(skin.bones.count) || index.rounded() != index) {
                    valid = false
                }
                sum += weight
            }
            if !valid || abs(sum - 1) > 0.02 { invalid += 1 }
        }
        invalidVertices = invalid
    }
    private static func value(_ source: SCNGeometrySource, vector: Int, component: Int) -> Double? {
        let stride =
            source.dataStride > 0 ? source.dataStride : source.bytesPerComponent * source.componentsPerVector
        let offset = source.dataOffset + vector * stride + component * source.bytesPerComponent
        guard offset >= 0, offset + source.bytesPerComponent <= source.data.count else { return nil }
        return source.data.withUnsafeBytes { buffer -> Double? in
            if source.usesFloatComponents {
                if source.bytesPerComponent == 4 {
                    return Double(buffer.loadUnaligned(fromByteOffset: offset, as: Float.self))
                }
                if source.bytesPerComponent == 8 {
                    return buffer.loadUnaligned(fromByteOffset: offset, as: Double.self)
                }
            } else {
                switch source.bytesPerComponent {
                case 1: return Double(buffer.loadUnaligned(fromByteOffset: offset, as: UInt8.self))
                case 2: return Double(buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                case 4: return Double(buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
                default: return nil
                }
            }
            return nil
        }
    }
}
