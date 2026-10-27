import AppKit
import ForestCabinScene
import Foundation
import Metal
import PaperCatBehavior
import PaperCatRendering
import PopupBookCore
import SceneKit
import VolumeCatRendering

struct RenderingCosts: Codable {
    let kind: String
    let frames: Int
    let simulatedSeconds: Double
    let wallSeconds: Double
    let pixels: String
    let samples: Int
    let averageGPUms: Double
    let p95GPUms: Double
    let p95CPUAndWaitMs: Double
    let device: String
    let characterStyle: String
    let paced: Bool
    let frameBudgetOverruns: Int
    let observedMoods: [String]
    let configuration: String
}

@MainActor func run() throws {
    _ = NSApplication.shared
    let arguments = Array(CommandLine.arguments.dropFirst())
    let count = arguments.first.flatMap(Int.init) ?? (arguments.isEmpty ? 600 : -1)
    guard arguments.dropFirst().allSatisfy({ ["--paced", "--candidate"].contains($0) }) else {
        throw NSError(
            domain: "OffscreenCheck", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "参数应为帧数，后接可选的--paced（实时节拍）和--candidate（立体候选）。"])
    }
    let paced = CommandLine.arguments.contains("--paced")
    let candidate = CommandLine.arguments.contains("--candidate")
    guard count >= 120 && count <= 108000,
        let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue()
    else {
        throw CocoaError(.coderInvalidValue)
    }
    let world = ForestCabin()
    var character = PaperCat()
    let present: (CatPose, WorldContext) throws -> Void
    if candidate {
        let folder = URL(fileURLWithPath: "build/cat-candidate")
        let presenter = try VolumeCatPresenter(stage: world.stage, assets: folder)
        present = {
            presenter.update($0, in: $1)
            if let error = presenter.lastError {
                throw NSError(
                    domain: "OffscreenCheck", code: 3, userInfo: [NSLocalizedDescriptionKey: error])
            }
        }
    } else {
        let presenter = try PaperCatPresenter(stage: world.stage)
        present = { presenter.update($0, in: $1) }
    }
    let renderer = SCNRenderer(device: device, options: nil)
    renderer.scene = world.scene
    renderer.pointOfView = world.camera
    let width = 1600
    let height = 1100
    let sampleCount = 4
    let resolved = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    resolved.usage = [.renderTarget, .shaderRead]
    resolved.storageMode = .private
    let color = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    color.textureType = .type2DMultisample
    color.sampleCount = sampleCount
    color.usage = .renderTarget
    color.storageMode = .private
    let depth = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .depth32Float_stencil8, width: width, height: height, mipmapped: false)
    depth.textureType = .type2DMultisample
    depth.sampleCount = sampleCount
    depth.usage = .renderTarget
    depth.storageMode = .private
    guard let resolvedTexture = device.makeTexture(descriptor: resolved),
        let colorTexture = device.makeTexture(descriptor: color),
        let depthTexture = device.makeTexture(descriptor: depth)
    else { throw CocoaError(.coderInvalidValue) }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = colorTexture
    pass.colorAttachments[0].resolveTexture = resolvedTexture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .multisampleResolve
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0.98, 0.98, 0.93, 1)
    pass.depthAttachment.texture = depthTexture
    pass.depthAttachment.loadAction = .clear
    pass.depthAttachment.storeAction = .dontCare
    pass.depthAttachment.clearDepth = 1
    pass.stencilAttachment.texture = depthTexture
    pass.stencilAttachment.loadAction = .clear
    pass.stencilAttachment.storeAction = .dontCare
    var gpuTimes: [Double] = []
    var frameTimes: [Double] = []
    var moods = Set<CatMood>()
    var fold = FoldState()
    var overruns = 0
    let start = ProcessInfo.processInfo.systemUptime
    for frame in 0..<count {
        try autoreleasepool {
            let before = ProcessInfo.processInfo.systemUptime
            let time = Double(frame) / 60
            var context = WorldContext(progress: 1, clock: time, deltaTime: 1.0 / 60, stableDuration: time)
            if paced {
                let phase = frame % 3600
                fold.target = (2700..<2800).contains(phase) ? 0.5 : 1
                context = fold.advance(1.0 / 60)
                if phase == 360 { _ = character.interact(.gentleTouch, in: context) }
                if phase == 900 { _ = character.interact(.invite(.invitation), in: context) }
                if phase == 1800 { _ = character.interact(.greet, in: context) }
            }
            let output = character.advance(in: context)
            moods.insert(output.pose.mood)
            world.update(in: context, events: output.events)
            try present(output.pose, context)
            guard let command = queue.makeCommandBuffer() else { throw CocoaError(.coderInvalidValue) }
            renderer.render(
                atTime: time, viewport: CGRect(x: 0, y: 0, width: width, height: height),
                commandBuffer: command, passDescriptor: pass)
            command.commit()
            command.waitUntilCompleted()
            if let error = command.error { throw error }
            if frame >= 60 {
                let frameMs = (ProcessInfo.processInfo.systemUptime - before) * 1000
                frameTimes.append(frameMs)
                if frameMs > 1000.0 / 60 { overruns += 1 }
                if command.gpuEndTime > command.gpuStartTime, command.gpuStartTime > 0 {
                    gpuTimes.append((command.gpuEndTime - command.gpuStartTime) * 1000)
                }
            }
        }
        if paced {
            let remaining = start + Double(frame + 1) / 60 - ProcessInfo.processInfo.systemUptime
            if remaining > 0 { Thread.sleep(forTimeInterval: remaining) }
            if (frame + 1) % 3600 == 0 {
                print("离屏持续运行 \((frame + 1) / 60) 秒，完成 \(frame + 1) 帧；非窗口显示帧率。")
                fflush(stdout)
            }
        }
    }
    guard gpuTimes.count > 30 else {
        throw NSError(
            domain: "OffscreenCheck", code: 2, userInfo: [NSLocalizedDescriptionKey: "未取得足够GPU时间，不报告性能通过。"])
    }
    func p95(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
    }
    let report = RenderingCosts(
        kind: "离屏GPU成本；非实时窗口帧率、非用户相处验收", frames: count,
        simulatedSeconds: Double(count) / 60, wallSeconds: ProcessInfo.processInfo.systemUptime - start,
        pixels: "1600x1100", samples: sampleCount,
        averageGPUms: gpuTimes.reduce(0, +) / Double(gpuTimes.count),
        p95GPUms: p95(gpuTimes), p95CPUAndWaitMs: p95(frameTimes), device: device.name,
        characterStyle: candidate ? "立体候选（动作不完整）" : "默认纸猫", paced: paced,
        frameBudgetOverruns: overruns, observedMoods: moods.map(\.rawValue).sorted(),
        configuration: buildConfiguration)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(report), as: UTF8.self))
}
#if DEBUG
    let buildConfiguration = "Debug（调试构建）"
#else
    let buildConfiguration = "Release（优化构建）"
#endif
do { try MainActor.assumeIsolated { try run() } } catch {
    fputs("离屏成本检查失败：\(error)\n", stderr)
    exit(1)
}
