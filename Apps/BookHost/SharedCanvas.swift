import AppKit
import MacPlatform
import MetalKit
import PopupBookCore

@MainActor final class SharedCanvas: MTKView, MTKViewDelegate {
    var composition: HostComposition?
    var onWindow: ((NSWindow) -> Void)?
    var onCapture: ((MTLTexture) -> Void)?
    var onPresented: ((Double, String, Double) -> Void)?
    private var tracker: NSTrackingArea?
    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var shown: MTLTexture?
    override var acceptsFirstResponder: Bool { true }
    init(composition: HostComposition) {
        super.init(frame: .zero, device: composition.device)
        self.composition = composition
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = false
        preferredFramesPerSecond = 60
        delegate = self
        clearColor = MTLClearColor(red: 0.96, green: 0.94, blue: 0.88, alpha: 1)
        queue = device?.makeCommandQueue()
        let code = """
            #include <metal_stdlib>
            using namespace metal;
            struct Out {float4 position [[position]];float2 uv;};
            vertex Out bookVertex(uint id [[vertex_id]]){float2 p=float2((id<<1)&2,id&2);return{float4(p*2-1,0,1),float2(p.x,1-p.y)};}
            fragment float4 bookFragment(Out in [[stage_in]],texture2d<float> image [[texture(0)]]){constexpr sampler s(filter::linear);return image.sample(s,in.uv);}
            """
        if let device, let library = try? device.makeLibrary(source: code, options: nil) {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: "bookVertex")
            desc.fragmentFunction = library.makeFunction(name: "bookFragment")
            desc.colorAttachments[0].pixelFormat = colorPixelFormat
            pipeline = try? device.makeRenderPipelineState(descriptor: desc)
        }
    }
    required init(coder: NSCoder) { super.init(coder: coder) }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            window.acceptsMouseMovedEvents = true
            onWindow?(window)
        }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracker { removeTrackingArea(tracker) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [
                .mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect,
                .enabledDuringMouseDrag,
            ], owner: self)
        addTrackingArea(area)
        tracker = area
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        route(.down, event)
    }
    override func mouseDragged(with event: NSEvent) { route(.drag, event) }
    override func mouseUp(with event: NSEvent) { route(.up, event) }
    override func mouseMoved(with event: NSEvent) { route(.move, event) }
    override func mouseExited(with event: NSEvent) { composition?.coordinator.handle(.cancel) }
    override func cancelOperation(_ sender: Any?) { composition?.coordinator.handle(.cancel) }
    override func swipe(with event: NSEvent) {
        if event.deltaX > 0 {
            composition?.coordinator.move(-1)
        } else if event.deltaX < 0 {
            composition?.coordinator.move(1)
        }
    }
    private func route(_ kind: PagePointerKind, _ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        composition?.coordinator.handle(
            .pointer(
                PagePointer(
                    kind, x: min(1, max(0, p.x / max(1, bounds.width))),
                    y: min(1, max(0, p.y / max(1, bounds.height))), time: event.timestamp)))
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let composition else { return }
        let id = composition.coordinator.state.current
        if let id {
            composition.processes[id]?.setViewport(
                width: Int(drawableSize.width), height: Int(drawableSize.height))
        }
        composition.clock.pulse()
        let incoming = id.flatMap { composition.processes[$0]?.takeFrame() }
        guard let incoming else { return }
        shown = incoming.texture
        guard let drawable = currentDrawable, let command = queue?.makeCommandBuffer() else {
            incoming.release()
            return
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = clearColor
        if let encoder = command.makeRenderCommandEncoder(descriptor: pass) {
            if let shown, let pipeline {
                encoder.setRenderPipelineState(pipeline)
                encoder.setFragmentTexture(shown, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            }
            encoder.endEncoding()
        }
        drawable.addPresentedHandler { [weak self] frame in
            DispatchQueue.main.async {
                if frame.presentedTime > 0 {
                    self?.onPresented?(
                        (frame.presentedTime - incoming.inputTime) * 1000, incoming.caption,
                        frame.presentedTime)
                }
            }
        }
        command.present(drawable)
        command.addCompletedHandler { _ in
            DispatchQueue.main.async { [weak self] in
                self?.onCapture?(incoming.texture)
                incoming.release()
            }
        }
        command.commit()
    }
}
