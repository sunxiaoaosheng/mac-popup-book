import AppKit
import IOSurface
import MetalKit
import ProbeWire

final class Canvas: MTKView {
    var input: ((Double) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { route(event) }
    override func mouseDragged(with event: NSEvent) { route(event) }
    override func mouseUp(with event: NSEvent) { route(event) }
    private func route(_ event: NSEvent) {
        input?(min(1, max(0, convert(event.locationInWindow, from: nil).x / max(bounds.width, 1))))
    }
}
final class Probe: NSObject, MTKViewDelegate {
    let device = MTLCreateSystemDefaultDevice()!
    lazy var queue = device.makeCommandQueue()!
    let window = NSWindow(
        contentRect: NSRect(x: 100, y: 100, width: 1440, height: 960),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    lazy var view = Canvas(frame: NSRect(x: 0, y: 0, width: 1440, height: 960), device: device)
    var connection: NSXPCConnection?
    var textures: [MTLTexture] = []
    var free = Set(0..<3)
    var pending: (Int, Int, Double)?
    var sequence = 0
    var epoch = 0
    var frames = 0
    var latencies: [Double] = []
    var start = 0.0
    var lastFrame = 0.0
    var timer: Timer?
    var invalidations = 0
    var pid: Int32 = 0
    var healthy = false
    var stage = 0
    var resized = false
    var measured = false
    var value = 0.25
    lazy var pipeline: MTLRenderPipelineState = {
        let code = """
            #include <metal_stdlib>
            using namespace metal;
            struct Out { float4 position [[position]]; float2 uv; };
            vertex Out vertexMain(uint id [[vertex_id]]) {
              float2 p = float2((id << 1) & 2, id & 2);
              return {float4(p*2-1, 0, 1), float2(p.x, 1-p.y)};
            }
            fragment float4 fragmentMain(Out in [[stage_in]], texture2d<float> image [[texture(0)]]) {
              constexpr sampler s(filter::linear); return image.sample(s,in.uv);
            }
            """
        let library = try! device.makeLibrary(source: code, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "vertexMain")
        descriptor.fragmentFunction = library.makeFunction(name: "fragmentMain")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try! device.makeRenderPipelineState(descriptor: descriptor)
    }()
    var automatic: Bool { ProcessInfo.processInfo.arguments.contains("--check") }
    func launch() {
        window.title = "跨进程隔离样件"
        window.contentView = view
        view.delegate = self
        view.preferredFramesPerSecond = 60
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.input = { [weak self] value in self?.value = value }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        connect("red")
        if automatic {
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                self?.check()
            }
        }
    }
    func connect(_ name: String) {
        epoch += 1
        let token = epoch
        connection?.invalidate()
        textures = []
        free = Set(0..<3)
        pending = nil
        healthy = false
        let c = NSXPCConnection(serviceName: "local.ssr.isolation-probe.\(name)")
        connection = c
        c.remoteObjectInterface = probeInterface()
        c.invalidationHandler = { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.epoch == token else { return }
                self.invalidations += 1
                self.healthy = false
            }
        }
        c.interruptionHandler = c.invalidationHandler
        c.resume()
        let proxy = c.remoteObjectProxyWithErrorHandler { error in print("连接错误：", error) } as! ProbeService
        proxy.prepare(2880, height: 1920) { [weak self] a, b, d, pid in
            DispatchQueue.main.async {
                guard let self, self.epoch == token, let a, let b, let d else { return }
                let desc = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm, width: 2880, height: 1920, mipmapped: false)
                desc.usage = [.shaderRead, .renderTarget]
                desc.storageMode = .shared
                self.textures = [a, b, d].compactMap {
                    self.device.makeTexture(descriptor: desc, iosurface: $0, plane: 0)
                }
                self.pid = pid
                self.healthy = true
                self.start = ProcessInfo.processInfo.systemUptime
                self.lastFrame = self.start
                print("连接完成：", name, "独立进程：", pid, "主程序：", getpid())
            }
        }
    }
    func send(_ value: Double) {
        guard healthy, let slot = free.first, let proxy = connection?.remoteObjectProxy as? ProbeService
        else { return }
        free.remove(slot)
        sequence += 1
        let n = sequence
        let token = epoch
        let time = ProcessInfo.processInfo.systemUptime
        proxy.render(slot, sequence: n, value: value) { [weak self] slot, n in
            DispatchQueue.main.async {
                guard let self, self.epoch == token else { return }
                if let stale = self.pending { self.free.insert(stale.0) }
                self.pending = (slot, n, time)
            }
        }
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        send(value)
        guard let pending, textures.indices.contains(pending.0), let drawable = view.currentDrawable,
            let command = queue.makeCommandBuffer()
        else { return }
        self.pending = nil
        let slot = pending.0
        let token = epoch
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(textures[slot], index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        drawable.addPresentedHandler { [weak self] shown in
            DispatchQueue.main.async {
                guard let self, self.epoch == token, shown.presentedTime > 0 else { return }
                self.frames += 1
                self.latencies.append((shown.presentedTime - pending.2) * 1000)
            }
        }
        command.present(drawable)
        command.addCompletedHandler { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.epoch == token else { return }
                self.free.insert(slot)
                self.lastFrame = ProcessInfo.processInfo.systemUptime
            }
        }
        command.commit()
    }
    func check() {
        let now = ProcessInfo.processInfo.systemUptime
        if stage == 1, !measured, now - start > 2 {
            measured = true
            start = now
            frames = 0
            latencies = []
        }
        if stage == 1, now - start > 2, !resized {
            resized = true
            window.setContentSize(NSSize(width: 880, height: 680))
        }
        if stage == 1, now - start > 4, resized {
            window.setContentSize(NSSize(width: 1440, height: 960))
        }
        if stage == 0, healthy {
            // Test the complete IPC/GPU presentation path at display cadence; synthetic input, not physical latency.
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                self?.check()
            }
            stage = 1
        } else if stage == 1, now - start > 8 {
            let sorted = latencies.sorted()
            let p95 = sorted.isEmpty ? 999 : sorted[Int(Double(sorted.count - 1) * 0.95)]
            let fps = Double(frames) / (now - start)
            print("实测：帧率", fps, "合成输入至实际呈现p95毫秒", p95)
            guard fps >= 55, p95 <= 100 else {
                print("性能门槛失败")
                exit(2)
            }
            (connection?.remoteObjectProxy as? ProbeService)?.fail(1)
            stage = 2
            start = now
        } else if stage == 2, invalidations > 0 {
            print("崩溃隔离通过，主程序继续运行")
            stage = 3
            connect("blue")
        } else if stage == 3, healthy, now - start > 2 {
            (connection?.remoteObjectProxy as? ProbeService)?.fail(2)
            stage = 4
            start = now
        } else if stage == 4, now - lastFrame > 3 {
            // PID comes only from the signed bundled test service used by this connection.
            print("卡死检测通过，主程序继续运行")
            kill(pid, SIGKILL)
            connection?.invalidate()
            stage = 5
            connect("red")
        } else if stage == 5, healthy, now - start > 2 {
            print("恢复页面通过；验证完成")
            connection?.invalidate()
            NSApp.terminate(nil)
        }
        if stage == 2, now - start > 10 {
            print("崩溃检测超时")
            exit(3)
        }
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let probe = Probe()
setbuf(stdout, nil)
app.finishLaunching()
probe.launch()
let deadline = Timer.scheduledTimer(withTimeInterval: 40, repeats: false) { _ in
    print("样件总超时")
    exit(4)
}
app.run()
