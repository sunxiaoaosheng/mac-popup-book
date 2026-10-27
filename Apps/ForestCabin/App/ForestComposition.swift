import AppKit
import ForestCabinScene
import MacPlatform
import PaperCatBehavior
import PaperCatRendering
import PopupBookCore
import PopupBookRuntime
import SceneKit
import SceneKitRendering

/// The only production location that selects concrete implementations.
@MainActor final class ForestComposition {
    let world: ForestCabin
    private let character: PaperCatPresenter
    private let invitation: SCNNode
    let session: any BookSessionControl
    init(resources: URL, settings: any SettingsStore) throws {
        world = ForestCabin()
        invitation = try world.stage.anchor(.invitation)
        character = try PaperCatPresenter(stage: world.stage)
        var assets = [
            AudioAsset(
                id: SoundID("paper.fold"), url: resources.appendingPathComponent("Audio/paper.wav"),
                volume: 0.12),
            AudioAsset(
                id: SoundID("forest.ambience"), url: resources.appendingPathComponent("Audio/forest.wav"),
                volume: 0.045, loops: true),
        ]
        assets += CatAudio.greetingResources.map {
            AudioAsset(
                id: CatAudio.greeting, url: resources.appendingPathComponent("Audio/" + $0), volume: 0.15)
        }
        assets += CatAudio.footstepResources.map {
            AudioAsset(
                id: PaperCatSounds.footstep, url: resources.appendingPathComponent("Audio/" + $0),
                volume: 0.10)
        }
        assets.append(
            AudioAsset(
                id: SoundID("paper.fold"), url: resources.appendingPathComponent("Audio/paper-soft.wav"),
                volume: 0.12))
        assets.append(
            AudioAsset(
                id: PaperCatSounds.purr,
                url: resources.appendingPathComponent("Audio/" + CatAudio.purrResource),
                volume: 0.55, loops: true, autostart: false))
        let audio = try BundleAudio(assets: assets)
        let presenter = character
        let behavior = PaperCat(random: SeededRandom(seed: UInt64.random(in: UInt64.min...UInt64.max)))
        let store = try FileStateStore.applicationStore()
        session = try BookSession(
            character: behavior, scene: world, source: LidAngleSource(), clock: SystemFrameClock(),
            settings: settings, audio: audio, stateStore: store, wallClock: SystemWallClock()
        ) { pose, context in presenter.update(pose, in: context) }
        world.update(in: session.context, events: [])
        character.update(behavior.pose, in: session.context)
    }
    func configure(_ view: BookSceneView) {
        view.configure(world.stage)
        view.hits.register(character.cat, as: session.characterID)
        view.hits.register(character.windowCat, as: session.characterID)
        view.registerInvitation(invitation, anchor: .invitation, for: session.characterID)
        view.onInteraction = { [weak session] id, event in _ = session?.interact(with: id, interaction: event)
        }
    }
}
