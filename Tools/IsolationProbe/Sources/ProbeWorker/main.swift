import Foundation
import IOSurface
import Metal
import ProbeWire

final class Worker: NSObject, ProbeService {
    let device = MTLCreateSystemDefaultDevice()!
    lazy var queue = device.makeCommandQueue()!
    var surfaces: [IOSurface] = []
    var textures: [MTLTexture] = []
    func prepare(
        _ width: Int, height: Int, reply: @escaping (IOSurface?, IOSurface?, IOSurface?, Int32) -> Void
    ) {
        guard width > 0, height > 0, width <= 4096, height <= 4096 else {
            reply(nil, nil, nil, getpid())
            return
        }
        surfaces = (0..<3).compactMap { _ in
            IOSurface(properties: [
                .width: width, .height: height, .bytesPerElement: 4,
                .bytesPerRow: width * 4, .pixelFormat: 1_111_970_369,
            ])
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        textures = surfaces.compactMap { device.makeTexture(descriptor: desc, iosurface: $0, plane: 0) }
        guard textures.count == 3 else {
            reply(nil, nil, nil, getpid())
            return
        }
        reply(surfaces[0], surfaces[1], surfaces[2], getpid())
    }
    func render(_ slot: Int, sequence: Int, value: Double, reply: @escaping (Int, Int) -> Void) {
        guard textures.indices.contains(slot), let command = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = textures[slot]
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let blue = Bundle.main.bundleIdentifier?.hasSuffix("blue") == true
        pass.colorAttachments[0].clearColor = MTLClearColor(
            red: blue ? 0.1 : 0.65, green: value, blue: blue ? 0.7 : 0.1, alpha: 1)
        command.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
        command.addCompletedHandler { _ in reply(slot, sequence) }
        command.commit()
    }
    func fail(_ mode: Int) {
        if mode == 1 { exit(71) }
        if mode == 2 { while true { Thread.sleep(forTimeInterval: 1) } }
    }
}
final class Listener: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = probeInterface()
        connection.exportedObject = Worker()
        connection.resume()
        return true
    }
}
let delegate = Listener()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
