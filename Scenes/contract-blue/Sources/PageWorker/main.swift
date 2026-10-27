import Foundation
import Metal
import PageBehavior
import PageWorkerKit
import PopupBookCore

@MainActor final class SamplePage: RenderedBookPage {
    var state = Selection()
    func prepare(_ startup: PageStartup) throws {}
    func handle(_ input: PageInput) {
        if case .pointer(let event) = input, event.kind != .cancel { state.select(event.x) }
    }
    func advance(_ context: WorldContext) throws -> PagePresentation {
        PagePresentation(caption: "contract-blue \(Int(state.value * 100))", accessibility: "contract-blue")
    }
    func render(into texture: MTLTexture, command: MTLCommandBuffer, context: WorldContext) throws {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(
            red: 0.1, green: state.value, blue: 0.8, alpha: 1)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            throw PageError.unavailable
        }
        encoder.endEncoding()
    }
    func pause() -> Data? { nil }
    func finish() -> Data? { nil }
}
PageWorker.run { SamplePage() }
