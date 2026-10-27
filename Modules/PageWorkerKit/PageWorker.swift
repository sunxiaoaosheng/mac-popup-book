import Foundation
import IOSurface
import Metal
import PageTransport
import PopupBookCore

@MainActor public protocol RenderedBookPage: AnyObject {
    func prepare(_ startup: PageStartup) throws
    func handle(_ input: PageInput)
    func advance(_ context: WorldContext) throws -> PagePresentation
    func render(into texture: MTLTexture, command: MTLCommandBuffer, context: WorldContext) throws
    func pause() -> Data?
    func finish() -> Data?
}

private final class Worker: NSObject, PageService {
    let factory: @MainActor () throws -> any RenderedBookPage
    let device: MTLDevice?
    let queue: MTLCommandQueue?
    var page: (any RenderedBookPage)?
    var textures: [MTLTexture] = []
    var surfaces: [IOSurface] = []
    var epoch = -1
    var generation = 0
    var paused = false
    var activity: NSObjectProtocol?
    init(factory: @escaping @MainActor () throws -> any RenderedBookPage) {
        self.factory = factory
        device = MTLCreateSystemDefaultDevice()
        queue = device?.makeCommandQueue()
    }
    @MainActor func allocate(_ width: Int, _ height: Int) throws {
        guard let device, width > 0, height > 0, width <= 4096, height <= 4096 else {
            throw PageError.missingResources
        }
        let next = (0..<3).compactMap { _ in
            IOSurface(properties: [
                .width: width, .height: height, .bytesPerElement: 4,
                .bytesPerRow: ((width * 4 + 63) / 64) * 64,
                .pixelFormat: 1_111_970_369,
            ])
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]
        let targets = next.compactMap { device.makeTexture(descriptor: descriptor, iosurface: $0, plane: 0) }
        guard targets.count == 3 else { throw PageError.missingResources }
        surfaces = next
        textures = targets
    }
    func prepare(_ data: Data, reply: @escaping (IOSurface?, IOSurface?, IOSurface?, Data) -> Void) {
        DispatchQueue.main.async {
            var token = -1
            do {
                guard data.count < 2_100_000 else { throw PageError.invalidMessage }
                let request = try JSONDecoder().decode(PageStartup.self, from: data)
                token = request.epoch
                guard request.version == PageContract.version else { throw PageError.incompatibleContract }
                self.epoch = request.epoch
                UserDefaults.standard.setVolatileDomain(
                    ["AppleLanguages": request.languages], forName: UserDefaults.argumentDomain)
                let page = try self.factory()
                try page.prepare(request)
                self.page = page
                try self.allocate(request.width, request.height)
                guard let command = self.queue?.makeCommandBuffer() else { throw PageError.missingResources }
                try page.render(
                    into: self.textures[0], command: command,
                    context: WorldContext(progress: 1, clock: 0, deltaTime: 0, stableDuration: 0))
                let surfaces = self.surfaces
                let success = PagePrepared(epoch: token, pid: getpid())
                let failed = PagePrepared(epoch: token, pid: getpid(), error: .missingResources)
                command.addCompletedHandler { buffer in
                    if buffer.status == .completed {
                        reply(
                            surfaces[0], surfaces[1], surfaces[2],
                            (try? JSONEncoder().encode(success)) ?? Data())
                    } else {
                        reply(nil, nil, nil, (try? JSONEncoder().encode(failed)) ?? Data())
                    }
                }
                command.commit()
            } catch {
                let result = PagePrepared(
                    epoch: token, pid: getpid(), error: (error as? PageError) ?? .missingResources,
                    detail: error.localizedDescription)
                reply(nil, nil, nil, (try? JSONEncoder().encode(result)) ?? Data())
            }
        }
    }
    func resize(_ data: Data, reply: @escaping (IOSurface?, IOSurface?, IOSurface?, Data) -> Void) {
        DispatchQueue.main.async {
            do {
                let request = try JSONDecoder().decode(PageSurfaceRequest.self, from: data)
                guard request.epoch == self.epoch else { throw PageError.invalidMessage }
                try self.allocate(request.width, request.height)
                self.generation = request.generation
                reply(self.surfaces[0], self.surfaces[1], self.surfaces[2], data)
            } catch { reply(nil, nil, nil, Data()) }
        }
    }
    func render(_ data: Data, reply: @escaping (Data) -> Void) {
        DispatchQueue.main.async {
            guard data.count < 16384,
                let request = try? JSONDecoder().decode(PageFrameRequest.self, from: data),
                request.epoch == self.epoch, request.surfaceGeneration == self.generation,
                self.textures.indices.contains(request.slot), let page = self.page,
                let command = self.queue?.makeCommandBuffer()
            else {
                reply(Data())
                return
            }
            do {
                self.paused = false
                if self.activity == nil {
                    self.activity = ProcessInfo.processInfo.beginActivity(
                        options: .userInitiatedAllowingIdleSystemSleep, reason: "Render active book page")
                }
                let output = try page.advance(request.context)
                try page.render(into: self.textures[request.slot], command: command, context: request.context)
                let response = PageFrameReply(request: request, output: output)
                let encoded = (try? JSONEncoder().encode(response)) ?? Data()
                command.addCompletedHandler { buffer in reply(buffer.status == .completed ? encoded : Data())
                }
                command.commit()
            } catch {
                reply(
                    (try? JSONEncoder().encode(
                        PageFrameReply(request: request, output: PagePresentation(), error: .unavailable)))
                        ?? Data())
            }
        }
    }
    func input(_ data: Data) {
        DispatchQueue.main.async {
            guard data.count < 16384,
                let request = try? JSONDecoder().decode(PageInputRequest.self, from: data),
                request.epoch == self.epoch, !self.paused
            else { return }
            if case .pointer(let pointer) = request.input, !pointer.valid { return }
            self.page?.handle(request.input)
        }
    }
    func suspend(_ epoch: Int, reply: @escaping (Data?) -> Void) {
        DispatchQueue.main.async {
            guard self.epoch == epoch else {
                reply(nil)
                return
            }
            self.paused = true
            if let activity = self.activity {
                ProcessInfo.processInfo.endActivity(activity)
                self.activity = nil
            }
            reply(self.page?.pause())
        }
    }
    func finish(_ epoch: Int, reply: @escaping (Data?) -> Void) {
        DispatchQueue.main.async {
            guard self.epoch == epoch else {
                reply(nil)
                return
            }
            if let activity = self.activity {
                ProcessInfo.processInfo.endActivity(activity)
                self.activity = nil
            }
            let saved = self.page?.finish()
            self.page = nil
            self.textures = []
            self.surfaces = []
            reply(saved)
        }
    }
    func disconnected() {
        DispatchQueue.main.async {
            if let activity = self.activity {
                ProcessInfo.processInfo.endActivity(activity)
                self.activity = nil
            }
            self.page = nil
            self.textures = []
            self.surfaces = []
        }
    }
    func injectFault(_ mode: Int) {
        guard (Bundle.main.object(forInfoDictionaryKey: "BookTestService") as? Bool) == true else { return }
        DispatchQueue.main.async {
            if mode == 1 { exit(71) }
            if mode == 2 { while true { Thread.sleep(forTimeInterval: 1) } }
        }
    }
}
private final class WorkerListener: NSObject, NSXPCListenerDelegate {
    let factory: @MainActor () throws -> any RenderedBookPage
    init(_ factory: @escaping @MainActor () throws -> any RenderedBookPage) { self.factory = factory }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = pageServiceInterface()
        let worker = Worker(factory: factory)
        connection.exportedObject = worker
        connection.invalidationHandler = { worker.disconnected() }
        connection.resume()
        return true
    }
}
public enum PageWorker {
    public static func run(factory: @escaping @MainActor () throws -> any RenderedBookPage) -> Never {
        let delegate = WorkerListener(factory)
        let listener = NSXPCListener.service()
        listener.delegate = delegate
        listener.resume()
        withExtendedLifetime(delegate) { RunLoop.main.run() }
        exit(0)
    }
}
