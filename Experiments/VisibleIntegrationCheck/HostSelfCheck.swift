import AppKit
import Foundation
import MacPlatform
import Metal
import PopupBookCore
import PopupBookRuntime

/// Explicit preview-only harness. Synthetic inputs and lifecycle changes are labeled in output.
@MainActor final class HostSelfCheck {
    private unowned let model: HostModel
    private var timer: Timer?
    private var captureName: String?
    private var debugTime = 0.0
    private var stage = 0
    private var since = 0.0
    private var deadline = 0.0
    private var frames = 0
    private var latencies: [Double] = []
    private var inputLatencies: [Double] = []
    private var expected: String?
    private var inputTime = 0.0
    private var samples = 0
    private var turns = 0
    private var turnTarget: String?
    private var pauseProgress = 0.0
    private var ownedPIDs: Set<Int32> = []
    init(model: HostModel) { self.model = model }
    func start() {
        setbuf(stdout, nil)
        since = ProcessInfo.processInfo.systemUptime
        deadline = since + 120
        // Explicit QA window stays visible while tools return focus; this is not the production lifecycle policy.
        model.canvas?.window?.level = .floating
        model.canvas?.window?.collectionBehavior.insert(.canJoinAllSpaces)
        model.canvas?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        print("开始整书跨进程检查：临时存储、手动角度、程序注入输入与生命周期，非人工开合。")
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
    }
    func presented(_ latency: Double, _ caption: String, _ time: Double) {
        guard stage == 1 else { return }
        frames += 1
        latencies.append(latency)
        if let expected, caption == expected {
            inputLatencies.append((time - inputTime) * 1000)
            self.expected = nil
        }
    }
    private var currentPort: MacPlatform.PageProcessConnection? {
        model.coordinator.state.current.flatMap { model.composition.processes[$0] }
    }
    private func check(_ condition: Bool, _ message: String) {
        if !condition {
            print("失败：", message)
            model.coordinator.stop()
            exit(2)
        }
    }
    private func step() {
        let now = ProcessInfo.processInfo.systemUptime
        check(now < deadline, "整书测试总超时")
        let coordinator = model.coordinator
        let state = coordinator.state
        if now - debugTime > 2 {
            debugTime = now
            print(
                "阶段：", stage, "切页次数：", turns, "目标：", state.target ?? "无", "启动状态：", state.phase,
                state.current ?? "无", state.active, state.pageStates, "画面尺寸：",
                model.canvas?.drawableSize ?? .zero, "暂停：", model.canvas?.isPaused ?? true, "样本：", samples,
                "期望：", expected ?? "无", "内容：", state.output.caption, "呈现帧：", frames, "应用前台：", NSApp.isActive,
                "窗口可见：", model.canvas?.window?.occlusionState.contains(.visible) ?? false)
        }
        if coordinator.registry.pages.count == 1, coordinator.registry.pages.first?.id == "forest-cabin" {
            forestStep(now)
            return
        }
        if let pid = currentPort?.pid, pid > 0 { ownedPIDs.insert(pid) }
        switch stage {
        case 0:
            if state.phase == .idle, currentPort?.ready == true, now - since > 2 {
                stage = 1
                since = now
                frames = 0
                print("样页已显示，开始稳定帧率和输入采样。")
            }
        case 1:
            if expected != nil, now - inputTime > 1 {
                check(false, "输入未呈现：\(expected ?? "")，当前\(state.output.caption)")
            }
            if expected == nil, samples < 50 {
                let value = samples % 2 == 0 ? 0.8 : 0.2
                samples += 1
                inputTime = now
                expected = "\(state.current ?? "") \(Int(value*100))"
                coordinator.handle(.pointer(PagePointer(.down, x: value, y: 0.5, time: now)))
                coordinator.handle(.pointer(PagePointer(.drag, x: value, y: 0.6, time: now + 0.01)))
                coordinator.handle(.pointer(PagePointer(.up, x: value, y: 0.6, time: now + 0.02)))
                coordinator.handle(.cancel)
            }
            if samples == 50, expected == nil, now - since >= 8 {
                let fps = Double(frames) / (now - since)
                let p95 = percentile(inputLatencies)
                print("稳定帧率：", fps, "；50次合成互动至实际呈现p95毫秒：", p95, "；帧管线p95毫秒：", percentile(latencies))
                check(fps >= 55 && p95 <= 100, "性能门槛")
                currentPort?.injectFault(1)
                stage = 2
                since = now
            }
        case 2:
            if let id = state.current, case .failed = state.pageStates[id] {
                print("场景退出隔离通过，目录状态仍可读取。")
                coordinator.move(1)
                stage = 3
                since = now
            }
        case 3:
            if state.phase == .idle, currentPort?.ready == true {
                print("其他页面成功运行。")
                currentPort?.injectFault(2)
                stage = 4
                since = now
            }
        case 4:
            if let id = state.current, case .failed(.stalled) = state.pageStates[id] {
                print("场景卡死隔离通过，正在重试。")
                coordinator.open(id)
                stage = 5
                since = now
            }
        case 5:
            if state.phase == .idle, currentPort?.ready == true {
                stage = 6
                since = now
                coordinator.setActive(false)
                pauseProgress = state.progress
            }
        case 6:
            if now - since > 1 {
                check(coordinator.state.progress == pauseProgress, "暂停时状态推进")
                coordinator.setActive(true)
                stage = 7
                since = now
            }
        case 7:
            if state.phase == .idle, currentPort?.ready == true, now - since > 0.2 {
                if let target = turnTarget { check(state.current == target, "切页未到达目标：\(target)") }
                if turns >= 20 {
                    print("二十次切页与暂停恢复通过。")
                    model.composition.shutdown()
                    stage = 8
                    since = now
                } else {
                    let ids = coordinator.registry.pages.map(\.id)
                    let next = ids.first(where: { $0 != state.current })!
                    turnTarget = next
                    coordinator.open(next)
                    turns += 1
                    since = now
                }
            }
        case 8:
            if now - since > 2 {
                let alive = ownedPIDs.filter { kill($0, 0) == 0 }
                check(alive.isEmpty, "残留已知场景进程：\(alive)")
                print("进程、声音作用域释放检查完成；整书测试通过。")
                timer?.invalidate()
                NSApp.terminate(nil)
            }
        default: break
        }
    }
    private func forestStep(_ now: Double) {
        let coordinator = model.coordinator
        check(!model.failed, "森林场景故障")
        switch stage {
        case 0:
            if coordinator.state.phase == .idle, now - since > 6 {
                stage = 12
                since = now
                captureName = "open"
            }
        case 12:
            if now - since > 1 {
                stage = 1
                since = now
                frames = 0
                latencies = []
            }
        case 1:
            if now - since > 8 {
                let fps = Double(frames) / (now - since)
                print("森林实际呈现帧率：", fps, "；帧管线p95毫秒：", percentile(latencies))
                check(fps >= 55 && percentile(latencies) <= 100, "森林性能门槛")
                coordinator.handle(.action("gentle-touch"))
                stage = 2
                since = now
            }
        case 2:
            if now - since > 0.4 {
                print("抚摸状态：", coordinator.state.output.accessibility)
                check(
                    coordinator.state.output.accessibility.contains("轻抚")
                        || coordinator.state.output.accessibility.contains("petting"), "抚摸回应")
                captureName = "petting"
                stage = 3
                since = now
            }
        case 3:
            if now - since > 0.3 {
                coordinator.handle(.action("invite-closer"))
                stage = 4
                since = now
            }
        case 4:
            if now - since > 0.4 {
                print("邀请状态：", coordinator.state.output.accessibility)
                check(
                    coordinator.state.output.accessibility.contains("坐坐")
                        || coordinator.state.output.accessibility.contains("Moving"), "邀请回应")
                captureName = "invitation"
                stage = 5
                since = now
            }
        case 5:
            if now - since > 0.3 {
                coordinator.setManual(0.5)
                stage = 6
                since = now
            }
        case 6:
            if now - since > 0.8 {
                captureName = "half"
                stage = 7
                since = now
            }
        case 7:
            if now - since > 0.3 {
                coordinator.setManual(0.02)
                stage = 8
                since = now
            }
        case 8:
            if now - since > 1 {
                captureName = "closed"
                stage = 9
                since = now
            }
        case 9:
            if now - since > 0.3 {
                coordinator.setManual(1)
                stage = 10
                since = now
            }
        case 10:
            if now - since > 5 {
                captureName = "reopened"
                stage = 11
                since = now
            }
        case 11:
            if now - since > 0.3 {
                print("森林开合、互动与恢复注入检查通过；默认未播放声音、未使用真实存档。")
                coordinator.stop()
                timer?.invalidate()
                NSApp.terminate(nil)
            }
        default: break
        }
    }
    func capture(_ texture: MTLTexture) {
        guard let name = captureName else { return }
        captureName = nil
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--capture-dir"), arguments.indices.contains(index + 1)
        else { return }
        let folder = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let size = texture.width * texture.height * 4
            var data = Data(count: size)
            data.withUnsafeMutableBytes { pointer in
                if let address = pointer.baseAddress {
                    texture.getBytes(
                        address, bytesPerRow: texture.width * 4,
                        from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
                }
            }
            guard let provider = CGDataProvider(data: data as CFData),
                let image = CGImage(
                    width: texture.width, height: texture.height, bitsPerComponent: 8, bitsPerPixel: 32,
                    bytesPerRow: texture.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(
                        .byteOrder32Little), provider: provider, decode: nil, shouldInterpolate: false,
                    intent: .defaultIntent),
                let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            else { throw PageError.unavailable }
            try png.write(to: folder.appendingPathComponent(name + ".png"))
        } catch { check(false, "无法保存渲染证据：\(error)") }
    }
    private func percentile(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return .infinity }
        let sorted = values.sorted()
        return sorted[Int(Double(sorted.count - 1) * 0.95)]
    }
}
