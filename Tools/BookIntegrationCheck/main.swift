import Foundation
import ImageIO
import MacPlatform
import Metal
import PopupBookCore
import PopupBookRuntime
import UniformTypeIdentifiers

extension PageProcessConnection: PageProcessPort {}

@MainActor final class Check {
    let clock = SystemFrameClock()
    let source = SilentSource()
    let device: MTLDevice
    let queue: MTLCommandQueue
    let supervisor = PageProcessSupervisor()
    var coordinator: BookCoordinator!
    var ports: [String: PageProcessConnection] = [:]
    var timer: Timer?
    var stage = 0
    var since = 0.0
    var deadline = 0.0
    var frames = 0
    var pipeline: [Double] = []
    var feedback: [Double] = []
    var expected: String?
    var inputTime = 0.0
    var samples = 0
    var turns = 0
    var turnTarget: String?
    var pids: Set<Int32> = []
    var pauseProgress = 0.0
    var captureName: String?
    var copied: MTLTexture?
    var forest: Bool
    var consumed = false
    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
            let resources = Bundle.main.resourceURL
        else { throw PageError.missingResources }
        self.device = device
        self.queue = queue
        let json =
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: resources.appendingPathComponent("published-pages.json")))
            as? [String: Any]
        let ids = json?["pages"] as? [String] ?? []
        let descriptors = ids.compactMap {
            try? Data(contentsOf: resources.appendingPathComponent("Pages/\($0).json"))
        }
        let registry = PageRegistry(descriptors: descriptors, published: ids)
        forest = ids == ["forest-cabin"]
        guard forest || registry.pages.count >= 2 else { throw PageError.invalidDescriptor }
        coordinator = BookCoordinator(
            registry: registry, source: source, clock: clock, settings: CheckSettings(),
            wallClock: SystemWallClock()
        ) { [weak self] page in
            guard let self else { return DeadPort() }
            let path = Bundle.main.bundleURL.appendingPathComponent(
                "Contents/XPCServices/\(page.id).xpc/Contents/MacOS/\(page.product)"
            ).path
            let port = PageProcessConnection(
                service: page.service, device: device, supervisor: self.supervisor, expectedPath: path,
                restore: { (nil, nil) })
            port.setViewport(width: 1600, height: 1100)
            self.ports[page.id] = port
            return port
        }
        coordinator.onChange = { [weak self] in self?.consume() }
        coordinator.setFollowing(false)
    }
    func start() {
        setbuf(stdout, nil)
        since = clock.now
        deadline = since + 120
        print("后台进程验收：无窗口、无焦点操作、无真实存档；1600×1100像素离屏GPU消费。数据不代表屏幕呈现帧率。")
        coordinator.setActive(true)
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
    }
    func consume() {
        guard let id = coordinator.state.current, let port = ports[id], let frame = port.takeFrame() else {
            return
        }
        if port.pid > 0 { pids.insert(port.pid) }
        if copied?.width != frame.texture.width || copied?.height != frame.texture.height {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm_srgb, width: frame.texture.width, height: frame.texture.height,
                mipmapped: false)
            desc.storageMode = .private
            desc.usage = .shaderRead
            copied = device.makeTexture(descriptor: desc)
        }
        guard let target = copied, let command = queue.makeCommandBuffer(),
            let blit = command.makeBlitCommandEncoder()
        else {
            frame.release()
            fail("后台GPU消费失败")
        }
        blit.copy(
            from: frame.texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
            sourceSize: MTLSize(width: target.width, height: target.height, depth: 1), to: target,
            destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
        blit.endEncoding()
        command.addCompletedHandler { [weak self] buffer in
            DispatchQueue.main.async {
                guard let self else {
                    frame.release()
                    return
                }
                if buffer.status != .completed { self.fail("GPU消费错误") }
                self.consumed = true
                let now = self.clock.now
                if self.stage == 1 {
                    self.frames += 1
                    self.pipeline.append((now - frame.inputTime) * 1000)
                    if frame.caption == self.expected {
                        self.feedback.append((now - self.inputTime) * 1000)
                        self.expected = nil
                    }
                }
                if let name = self.captureName {
                    self.captureName = nil
                    self.capture(frame.texture, name: name)
                }
                frame.release()
            }
        }
        command.commit()
    }
    func step() {
        let now = clock.now
        guard now < deadline else { fail("后台验收总超时，阶段\(stage)") }
        if forest {
            forestStep(now)
            return
        }
        let state = coordinator.state
        switch stage {
        case 0:
            if consumed, state.phase == .idle, now - since > 2 {
                stage = 1
                since = now
                frames = 0
                pipeline = []
            }
        case 1:
            if expected != nil, now - inputTime > 1 { fail("互动未返回预期状态") }
            if expected == nil, samples < 50 {
                let value = samples % 2 == 0 ? 0.8 : 0.2
                samples += 1
                inputTime = now
                expected = "\(state.current ?? "") \(Int(value*100))"
                for (kind, y) in [(PagePointerKind.down, 0.5), (.drag, 0.6), (.up, 0.6)] {
                    coordinator.handle(.pointer(PagePointer(kind, x: value, y: y, time: now)))
                }
                coordinator.handle(.cancel)
            }
            if samples == 50, expected == nil, now - since > 8 {
                let rate = Double(frames) / (now - since)
                print("离屏消费每秒帧数：", rate, "；50次注入反馈p95毫秒：", p95(feedback), "；传输消费p95毫秒：", p95(pipeline))
                require(rate >= 55 && p95(feedback) <= 100, "后台管线性能")
                current?.injectFault(1)
                stage = 2
                since = now
            }
        case 2:
            if failed(state.current) {
                print("退出隔离通过")
                coordinator.move(1)
                stage = 3
                since = now
            }
        case 3:
            if state.phase == .idle, current?.ready == true {
                print("其他页可运行")
                current?.injectFault(2)
                stage = 4
                since = now
            }
        case 4:
            if let id = state.current, case .failed(.stalled) = state.pageStates[id] {
                print("卡死隔离通过")
                coordinator.open(id)
                stage = 5
                since = now
            }
        case 5:
            if state.phase == .idle, current?.ready == true {
                print("手动重试通过")
                coordinator.setActive(false)
                pauseProgress = state.progress
                stage = 6
                since = now
            }
        case 6:
            if now - since > 1 {
                require(coordinator.state.progress == pauseProgress, "暂停仍推进")
                coordinator.setActive(true)
                stage = 7
                since = now
            }
        case 7:
            if state.phase == .idle, current?.ready == true, now - since > 0.2 {
                if let turnTarget { require(state.current == turnTarget, "未到达切页目标") }
                if turns == 20 {
                    print("连续二十次切页通过")
                    coordinator.stop()
                    supervisor.shutdown()
                    stage = 8
                    since = now
                } else {
                    guard
                        let target = coordinator.registry.pages.map(\.id).first(where: { $0 != state.current }
                        )
                    else { fail("缺少第二个测试页") }
                    turnTarget = target
                    coordinator.open(target)
                    turns += 1
                    since = now
                }
            }
        case 8:
            if now - since > 1 {
                require(pids.allSatisfy { kill($0, 0) != 0 }, "退出后残留已知子进程")
                print("后台故障、恢复、暂停、切页、进程回收全部通过")
                exit(0)
            }
        default: break
        }
    }
    var current: PageProcessConnection? { coordinator.state.current.flatMap { ports[$0] } }
    func failed(_ id: String?) -> Bool {
        guard let id else { return false }
        if case .failed = coordinator.state.pageStates[id] { return true }
        return false
    }
    func forestStep(_ now: Double) {
        require(!failed(coordinator.state.current), "森林场景错误")
        switch stage {
        case 0:
            if consumed, coordinator.state.phase == .idle, now - since > 6 {
                captureName = "open"
                stage = 12
                since = now
            }
        case 12:
            if now - since > 1 {
                stage = 1
                since = now
                frames = 0
                pipeline = []
            }
        case 1:
            if now - since > 8 {
                let rate = Double(frames) / (now - since)
                print("森林离屏消费每秒帧数：", rate, "；传输消费p95毫秒：", p95(pipeline))
                require(rate >= 55 && p95(pipeline) <= 100, "森林后台管线性能")
                coordinator.handle(.action("gentle-touch"))
                stage = 2
                since = now
            }
        case 2:
            if now - since > 0.4 {
                let value = coordinator.state.output.accessibility
                print("抚摸：", value)
                require(value.contains("轻抚") || value.contains("petting"), "轻抚未回应")
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
                let value = coordinator.state.output.accessibility
                print("邀请：", value)
                require(value.contains("坐坐") || value.contains("Moving"), "邀请未回应")
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
                coordinator.stop()
                supervisor.shutdown()
                print("森林后台开合、互动、恢复通过；声音未开启，真实存档未访问")
                exit(0)
            }
        default: break
        }
    }
    func capture(_ texture: MTLTexture, name: String) {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--capture-dir"), args.indices.contains(index + 1) else {
            return
        }
        do {
            let directory = URL(fileURLWithPath: args[index + 1])
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var bytes = Data(count: texture.width * texture.height * 4)
            bytes.withUnsafeMutableBytes { pointer in
                if let address = pointer.baseAddress {
                    texture.getBytes(
                        address, bytesPerRow: texture.width * 4,
                        from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
                }
            }
            guard let provider = CGDataProvider(data: bytes as CFData),
                let image = CGImage(
                    width: texture.width, height: texture.height, bitsPerComponent: 8, bitsPerPixel: 32,
                    bytesPerRow: texture.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(
                        .byteOrder32Little), provider: provider, decode: nil, shouldInterpolate: false,
                    intent: .defaultIntent),
                let destination = CGImageDestinationCreateWithURL(
                    directory.appendingPathComponent(name + ".png") as CFURL,
                    UTType.png.identifier as CFString, 1, nil)
            else { throw PageError.unavailable }
            CGImageDestinationAddImage(destination, image, nil)
            require(CGImageDestinationFinalize(destination), "图片写入失败")
        } catch { fail("后台图像证据：\(error)") }
    }
    func p95(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return .infinity }
        let sorted = values.sorted()
        return sorted[Int(Double(sorted.count - 1) * 0.95)]
    }
    func require(_ value: Bool, _ message: String) { if !value { fail(message) } }
    func fail(_ message: String) -> Never {
        print("失败：", message)
        coordinator?.stop()
        supervisor.shutdown()
        exit(2)
    }
}
@MainActor final class SilentSource: AngleSource {
    func start(_ callback: @escaping @MainActor (AngleSample) -> Void) {}
    func stop() {}
}
@MainActor final class CheckSettings: SettingsStore {
    var openAngle = 105.0
    var soundEnabled = false
}
@MainActor final class DeadPort: PageProcessPort {
    var onReady: (() -> Void)?
    var onFrame: ((PagePresentation) -> Void)?
    var onFailure: ((PageError) -> Void)?
    func start(epoch: Int) { onFailure?(.unavailable) }
    func advance(_ context: WorldContext) {}
    func handle(_ input: PageInput) {}
    func pause() {}
    func stop() {}
}
@MainActor func sensorProbe() -> Never {
    let source = LidAngleSource()
    var total = 0
    var valid = 0
    var last: Double?
    source.start { sample in
        total += 1
        if let angle = sample.angle {
            valid += 1
            last = angle
        }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
        source.stop()
        print("后台真实铰链读取：样本\(total)，有效\(valid)，最后角度\(last.map{String($0)} ?? "不可用")；非物理合盖验收。")
        exit(0)
    }
    RunLoop.main.run()
    exit(2)
}
@MainActor func main() {
    if ProcessInfo.processInfo.arguments.contains("--sensor-only") { sensorProbe() }
    do {
        let check = try Check()
        check.start()
        withExtendedLifetime(check) { RunLoop.main.run() }
    } catch {
        fputs("后台验收无法启动：\(error)\n", stderr)
        exit(2)
    }
}
MainActor.assumeIsolated { main() }
