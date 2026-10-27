import AppKit
import MacPlatform
import MetalKit
import PopupBookCore

@MainActor final class SharedCanvas: MTKView, MTKViewDelegate {
    var composition: HostComposition?
    var onWindow: ((NSWindow) -> Void)?
    private var tracker: NSTrackingArea?
    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var shown: MTLTexture?
    override var acceptsFirstResponder: Bool { true }
    init(composition: HostComposition) {
        super.init(frame: .zero, device: composition.device)
        self.composition = composition
        colorPixelFormat = .bgra8Unorm_srgb
        framebufferOnly = false
        preferredFramesPerSecond = 60
        delegate = self
        clearColor = MTLClearColor(red: 0.96, green: 0.94, blue: 0.88, alpha: 1)
        queue = device?.makeCommandQueue()
        let code = """
            #include <metal_stdlib>
            using namespace metal;
            struct Out {float4 position [[position]];float2 uv;};
            vertex Out bookVertex(uint id [[vertex_id]],constant float &angle [[buffer(0)]]){float2 p=float2(id&1,id>>1);float2 xy=p*2-1;float depth=sin(angle)*p.x*0.18;return{float4(-1+2*p.x*cos(angle),xy.y*(1-depth),0,1),float2(p.x,1-p.y)};}
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
        guard let drawable = currentDrawable, let command = queue?.makeCommandBuffer() else {
            incoming?.release()
            return
        }
        if let incoming {
            if shown?.width != incoming.texture.width || shown?.height != incoming.texture.height {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm_srgb, width: incoming.texture.width,
                    height: incoming.texture.height,
                    mipmapped: false)
                descriptor.storageMode = .private
                descriptor.usage = .shaderRead
                shown = device?.makeTexture(descriptor: descriptor)
            }
            if let shown, let blit = command.makeBlitCommandEncoder() {
                blit.copy(
                    from: incoming.texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
                    sourceSize: MTLSize(width: shown.width, height: shown.height, depth: 1), to: shown,
                    destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
                blit.endEncoding()
            }
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
                var angle: Float =
                    composition.coordinator.state.phase == .turning
                    ? Float(composition.coordinator.state.turnProgress) * Float.pi : 0
                encoder.setVertexBytes(&angle, length: MemoryLayout<Float>.size, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
            encoder.endEncoding()
        }
        command.present(drawable)
        command.addCompletedHandler { _ in
            DispatchQueue.main.async {
                incoming?.release()
            }
        }
        command.commit()
    }
}
