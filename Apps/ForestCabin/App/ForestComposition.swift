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
    let session: any BookSessionControl
    init(resources: URL, settings: any SettingsStore) throws {
        world = ForestCabin()
        character = try PaperCatPresenter(stage: world.stage)
        let assets = [
            AudioAsset(
                id: SoundID("paper.fold"), url: resources.appendingPathComponent("Audio/paper.wav"),
                volume: 0.12),
            AudioAsset(
                id: CatAudio.greeting,
                url: resources.appendingPathComponent("Audio/" + CatAudio.greetingResource), volume: 0.15),
            AudioAsset(
                id: SoundID("forest.ambience"), url: resources.appendingPathComponent("Audio/forest.wav"),
                volume: 0.045, loops: true),
        ]
        let audio = try BundleAudio(assets: assets)
        let presenter = character
        let behavior = PaperCat()
        session = try BookSession(
            character: behavior, scene: world, source: LidAngleSource(), clock: SystemFrameClock(),
            settings: settings, audio: audio
        ) { pose, context in presenter.update(pose, in: context) }
        world.update(in: session.context, events: [])
        character.update(behavior.pose, in: session.context)
    }
    func configure(_ view: BookSceneView) {
        view.configure(world.stage)
        view.hits.register(character.cat, as: session.characterID)
        view.hits.register(character.windowCat, as: session.characterID)
        view.onInteraction = { [weak session] id, event in _ = session?.interact(with: id, interaction: event)
        }
    }
}
