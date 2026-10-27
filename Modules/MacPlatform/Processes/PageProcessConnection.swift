import Darwin
import Foundation
import IOSurface
import Metal
import PageTransport
import PopupBookCore

/// Immutable texture lease crosses GPU completion queues; release is main-actor-only.
public struct SharedPageFrame: @unchecked Sendable {
    public let texture: MTLTexture
    public let sequence: Int
    public let inputTime: Double
    public let caption: String
    public let release: @MainActor @Sendable () -> Void
}

/// Owns a single bundled worker. Never blocks the main thread awaiting a reply.
@MainActor public final class PageProcessConnection {
    public var onReady: (() -> Void)?
    public var onFrame: ((PagePresentation) -> Void)?
    public var onFailure: ((PageError) -> Void)?
    public var onCheckpoint: ((Data) -> Void)?
    public private(set) var pid: Int32 = 0
    public private(set) var ready = false
    private let supervisor: PageProcessSupervisor
    private let expectedPath: String
    private let service: String
    private let device: MTLDevice
    private let restore: () -> (Data?, Data?)
    private var connection: NSXPCConnection?
    private var epoch = 0
    private var surfaceGeneration = 0
    private var free = Set(0..<3)
    private var textures: [MTLTexture] = []
    private var pending: (Int, Int, Double, String)?
    private var submittedClock: Double?
    private var sequence = 0
    private var acceptedSequence = 0
    private var desiredSize = (width: 2880, height: 1920)
    private var currentSize = (width: 2880, height: 1920)
    private var resizing = false
    private var lastResize = 0.0
    private var live = false
    private var processPath: String?
    private var checkpoint: Data?
    public init(
        service: String, device: MTLDevice, supervisor: PageProcessSupervisor, expectedPath: String,
        restore: @escaping () -> (Data?, Data?)
    ) {
        self.supervisor = supervisor
        self.expectedPath = expectedPath
        self.service = service
        self.device = device
        self.restore = restore
    }
    public func start(epoch: Int) {
        self.epoch = epoch
        surfaceGeneration = 0
        live = true
        ready = false
        currentSize = desiredSize
        supervisor.whenAvailable(
            service, wanted: { [weak self] in self?.live == true && self?.epoch == epoch },
            perform: { [weak self] in self?.connect(epoch: epoch) })
    }
    private func connect(epoch: Int) {
        let c = NSXPCConnection(serviceName: service)
        connection = c
        c.remoteObjectInterface = pageServiceInterface()
        c.interruptionHandler = { [weak self] in DispatchQueue.main.async { self?.failed(.unavailable) } }
        c.invalidationHandler = c.interruptionHandler
        c.resume()
        guard
            let proxy = c.remoteObjectProxyWithErrorHandler({ [weak self] _ in
                DispatchQueue.main.async { self?.failed(.unavailable) }
            }) as? PageService
        else {
            failed(.unavailable)
            return
        }
        let saved = restore()
        let request = PageStartup(
            epoch: epoch, width: currentSize.width, height: currentSize.height, state: saved.0,
            backup: saved.1)
        guard let data = try? JSONEncoder().encode(request) else {
            failed(.invalidMessage)
            return
        }
        proxy.prepare(data) { [weak self] a, b, d, result in
            DispatchQueue.main.async {
                guard let self, self.live, self.epoch == epoch else { return }
                guard result.count < 32768,
                    let reply = try? JSONDecoder().decode(PagePrepared.self, from: result),
                    reply.epoch == epoch
                else {
                    self.failed(.invalidMessage)
                    return
                }
                if let error = reply.error {
                    self.failed(error)
                    return
                }
                guard reply.pid == c.processIdentifier, reply.pid > 0 else {
                    self.failed(.invalidMessage)
                    return
                }
                self.pid = reply.pid
                self.processPath = self.path(of: reply.pid)
                guard self.processPath == self.expectedPath else {
                    self.failed(.invalidMessage)
                    return
                }
                if let identity = self.supervisor.identity(reply.pid, expectedPath: self.expectedPath) {
                    self.supervisor.register(self.service, identity: identity)
                }
                guard self.install(a, b, d) else {
                    self.failed(.missingResources)
                    return
                }
                self.ready = true
                self.onReady?()
            }
        }
    }
    private func install(_ a: IOSurface?, _ b: IOSurface?, _ d: IOSurface?) -> Bool {
        guard let a, let b, let d else { return false }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: currentSize.width, height: currentSize.height,
            mipmapped: false)
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = .shared
        for surface in [a, b, d] {
            guard surface.width == currentSize.width, surface.height == currentSize.height,
                surface.bytesPerElement == 4
            else { return false }
        }
        let new = [a, b, d].compactMap { device.makeTexture(descriptor: descriptor, iosurface: $0, plane: 0) }
        guard new.count == 3 else { return false }
        textures = new
        free = Set(0..<3)
        pending = nil
        return true
    }
    public func setViewport(width: Int, height: Int) {
        let factor = min(1, 4096.0 / Double(max(1, max(width, height))))
        desiredSize = (max(1, Int(Double(width) * factor)), max(1, Int(Double(height) * factor)))
    }
    public func advance(_ context: WorldContext) {
        guard live, ready, !resizing else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if desiredSize != currentSize, now - lastResize > 0.15 {
            resize()
            return
        }
        guard let slot = free.first, let proxy = connection?.remoteObjectProxy as? PageService else { return }
        free.remove(slot)
        sequence += 1
        let request = PageFrameRequest(
            epoch: epoch, surfaceGeneration: surfaceGeneration, sequence: sequence, slot: slot,
            context: context)
        guard let data = try? JSONEncoder().encode(request) else {
            failed(.invalidMessage)
            return
        }
        let sent = now
        proxy.render(data) { [weak self] data in
            DispatchQueue.main.async {
                guard let self, self.live, self.epoch == request.epoch,
                    self.surfaceGeneration == request.surfaceGeneration
                else { return }
                guard data.count < 2_100_000,
                    let frame = try? JSONDecoder().decode(PageFrameReply.self, from: data),
                    frame.request.epoch == request.epoch, frame.request.sequence == request.sequence,
                    frame.request.slot == slot, frame.request.surfaceGeneration == request.surfaceGeneration
                else {
                    self.failed(.invalidMessage)
                    return
                }
                guard request.sequence > self.acceptedSequence else {
                    self.free.insert(slot)
                    return
                }
                self.acceptedSequence = request.sequence
                if let error = frame.error {
                    self.failed(error)
                    return
                }
                guard frame.output.caption.count <= 8192, frame.output.actions.count <= 32,
                    (frame.output.checkpoint?.count ?? 0) <= 1_000_000
                else {
                    self.failed(.invalidMessage)
                    return
                }
                if let pending = self.pending { self.free.insert(pending.0) }
                self.pending = (slot, request.sequence, sent, frame.output.caption)
                if frame.output.canSave, let data = frame.output.checkpoint, data != self.checkpoint {
                    self.checkpoint = data
                    self.onCheckpoint?(data)
                }
                self.onFrame?(frame.output)
            }
        }
    }
    public func takeFrame() -> SharedPageFrame? {
        guard let pending, textures.indices.contains(pending.0) else { return nil }
        self.pending = nil
        let generation = surfaceGeneration
        return SharedPageFrame(
            texture: textures[pending.0], sequence: pending.1, inputTime: pending.2, caption: pending.3,
            release: { [weak self] in
                guard let self, self.live, self.surfaceGeneration == generation else { return }
                self.free.insert(pending.0)
            })
    }
    private func resize() {
        guard let proxy = connection?.remoteObjectProxy as? PageService else { return }
        resizing = true
        lastResize = ProcessInfo.processInfo.systemUptime
        surfaceGeneration += 1
        currentSize = desiredSize
        let token = surfaceGeneration
        pending = nil
        let request = PageSurfaceRequest(
            epoch: epoch, generation: token, width: currentSize.width, height: currentSize.height)
        guard let data = try? JSONEncoder().encode(request) else {
            failed(.invalidMessage)
            return
        }
        proxy.resize(data) { [weak self] a, b, d, result in
            DispatchQueue.main.async {
                guard let self, self.live, self.surfaceGeneration == token else { return }
                guard result == data, self.install(a, b, d) else {
                    self.failed(.invalidMessage)
                    return
                }
                self.resizing = false
            }
        }
    }
    public func handle(_ input: PageInput) {
        guard live, ready, let proxy = connection?.remoteObjectProxy as? PageService,
            let data = try? JSONEncoder().encode(PageInputRequest(epoch: epoch, input: input))
        else { return }
        proxy.input(data)
    }
    public func pause() {
        guard live, let proxy = connection?.remoteObjectProxy as? PageService else { return }
        proxy.suspend(epoch) { [weak self] data in
            DispatchQueue.main.async {
                guard let self, self.live, let data, data.count <= 1_000_000 else { return }
                self.onCheckpoint?(data)
            }
        }
    }
    public func stop() { close(terminating: false) }
    public func terminate() { close(terminating: true) }
    private func close(terminating: Bool) {
        guard live else { return }
        live = false
        ready = false
        let c = connection
        let identity = supervisor.identity(c?.processIdentifier ?? pid, expectedPath: expectedPath)
        if terminating, let identity { supervisor.retire(service, identity: identity) }
        c?.interruptionHandler = nil
        c?.invalidationHandler = nil
        (c?.remoteObjectProxy as? PageService)?.finish(epoch) { [weak self] data in
            DispatchQueue.main.async {
                if let data, data.count <= 1_000_000 { self?.onCheckpoint?(data) }
                c?.invalidate()
            }
        }
        textures = []
        pending = nil
        free = []
        connection = nil
        let supervisor = self.supervisor
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            c?.invalidate()
            if terminating, let identity { supervisor.terminate(identity) }
        }
    }
    /// Only test-only bundled services accept this request.
    public func injectFault(_ mode: Int) {
        (connection?.remoteObjectProxy as? PageService)?.injectFault(mode)
    }
    private func failed(_ error: PageError) {
        guard live else { return }
        onFailure?(error)
    }
    private func path(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let count = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return count > 0 ? String(cString: buffer) : nil
    }
}
