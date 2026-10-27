import ForestCabinScene
import Foundation
import Metal
import PageWorkerKit
import PaperCatBehavior
import PaperCatRendering
import PopupBookCore
import SceneKit
import SceneKitRendering

@MainActor final class ForestPage: RenderedBookPage {
    let world = ForestCabin()
    let presenter: PaperCatPresenter
    let renderer: SCNRenderer
    let pointer: PagePointerRouter
    var character = PaperCat(random: SeededRandom(seed: UInt64.random(in: UInt64.min...UInt64.max)))
    var context = WorldContext(progress: 1, clock: 0, deltaTime: 0, stableDuration: 0)
    var canSave = true
    var notice: String?
    private var interactionNotice: String?
    private var noticeUntil = 0.0
    var loops: Set<String> = []
    var resuming = false
    private var colorTarget: MTLTexture?
    private var depthTarget: MTLTexture?
    init() throws {
        presenter = try PaperCatPresenter(stage: world.stage)
        guard let device = MTLCreateSystemDefaultDevice() else { throw PageError.missingResources }
        renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = world.scene
        renderer.pointOfView = world.camera
        renderer.autoenablesDefaultLighting = false
        pointer = PagePointerRouter(renderer: renderer)
        pointer.hits.register(presenter.cat, as: character.id)
        pointer.hits.register(presenter.windowCat, as: character.id)
        pointer.registerInvitation(
            try world.stage.anchor(.invitation), anchor: .invitation, for: character.id)
        pointer.onInteraction = { [weak self] id, event in
            guard let self, id == self.character.id else { return }
            self.interact(event)
        }
    }
    func prepare(_ startup: PageStartup) throws {
        if let state = startup.state {
            do { try character.restorePersistentState(state) } catch {
                if let backup = startup.backup, (try? character.restorePersistentState(backup)) != nil {
                    notice = message("已从备份恢复相处记忆。", "Memories restored from backup.")
                } else {
                    canSave = false
                    notice = message(
                        "原存档已保留，本次仍可相处。", "The original save is safe. You can still spend time together.")
                }
            }
        }
        character.sessionBegan(at: startup.date)
    }
    func handle(_ input: PageInput) {
        switch input {
        case .pointer(let event): pointer.handle(event)
        case .cancel: pointer.cancel()
        case .action(let action):
            if action == "gentle-touch" { interact(.gentleTouch) }
            if action == "invite-closer" { interact(.invite(.invitation)) }
        }
    }
    private func interact(_ event: CharacterInteraction) {
        if character.interact(event, in: context) {
            interactionNotice = nil
            return
        }
        switch event {
        case .greet, .gentleTouch, .invite, .contactBegan:
            interactionNotice = character.interactionUnavailableMessage
            noticeUntil = context.clock + 2
        default: break
        }
    }
    func advance(_ context: WorldContext) throws -> PagePresentation {
        self.context = context
        if context.clock > noticeUntil { interactionNotice = nil }
        let output = character.advance(in: context)
        world.update(in: context, events: output.events)
        presenter.update(output.pose, in: context)
        var sounds = output.sounds.map { PageSound($0.rawValue, .play) }
        for command in output.soundCommands {
            switch command {
            case .beginLoop(let id):
                loops.insert(id.rawValue)
                sounds.append(PageSound(id.rawValue, .begin))
            case .endLoop(let id, let fade):
                loops.remove(id.rawValue)
                sounds.append(PageSound(id.rawValue, .end, fade: fade))
            }
        }
        if resuming {
            sounds += loops.map { PageSound($0, .begin) }
            resuming = false
        }
        return PagePresentation(
            caption: context.progress < 0.12 ? world.guidance.closedCaption : output.caption,
            accessibility: character.accessibilityState,
            actions: [
                PageAction("gentle-touch", title: message("轻轻摸摸", "Gently pet"), shortcut: "m"),
                PageAction("invite-closer", title: message("邀请靠近", "Come closer"), shortcut: "i"),
            ], sounds: sounds, checkpoint: canSave ? character.persistentState : nil, canSave: canSave,
            notice: interactionNotice ?? notice)
    }
    func render(into texture: MTLTexture, command: MTLCommandBuffer, context: WorldContext) throws {
        let size = CGSize(width: texture.width, height: texture.height)
        world.stage.fit(viewport: size)
        pointer.viewport = size
        if colorTarget?.width != texture.width || colorTarget?.height != texture.height {
            let color = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: texture.width, height: texture.height, mipmapped: false)
            color.textureType = .type2DMultisample
            color.sampleCount = 4
            color.storageMode = .private
            color.usage = .renderTarget
            colorTarget = texture.device.makeTexture(descriptor: color)
            let depth = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .depth32Float_stencil8, width: texture.width, height: texture.height,
                mipmapped: false)
            depth.textureType = .type2DMultisample
            depth.sampleCount = 4
            depth.storageMode = .private
            depth.usage = .renderTarget
            depthTarget = texture.device.makeTexture(descriptor: depth)
        }
        guard let colorTarget, let depthTarget else { throw PageError.missingResources }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = colorTarget
        pass.colorAttachments[0].resolveTexture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .multisampleResolve
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.96, green: 0.94, blue: 0.87, alpha: 1)
        pass.depthAttachment.texture = depthTarget
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 1
        pass.stencilAttachment.texture = depthTarget
        pass.stencilAttachment.loadAction = .clear
        pass.stencilAttachment.storeAction = .dontCare
        renderer.render(
            atTime: context.clock, viewport: CGRect(origin: .zero, size: size), commandBuffer: command,
            passDescriptor: pass)
    }
    func pause() -> Data? {
        pointer.cancel()
        resuming = true
        return canSave ? character.persistentState : nil
    }
    func finish() -> Data? {
        pointer.cancel()
        character.sessionEnded(at: context.wallDate)
        return canSave ? character.persistentState : nil
    }
    func message(_ zh: String, _ en: String) -> String {
        Bundle.preferredLocalizations(from: ["en", "zh-Hans"], forPreferences: Locale.preferredLanguages)
            .first == "zh-Hans" ? zh : en
    }
}
PageWorker.run { try ForestPage() }
