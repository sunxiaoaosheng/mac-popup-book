import Foundation
import MacPlatform
import Metal
import PopupBookCore
import PopupBookRuntime

extension PageProcessConnection: PageProcessPort {}

@MainActor final class HostComposition {
    let clock = DisplayFrameClock()
    let settings: any SettingsStore
    let registry: PageRegistry
    let device = MTLCreateSystemDefaultDevice()
    let preview: Bool
    let root: URL
    var coordinator: BookCoordinator!
    var processes: [String: PageProcessConnection] = [:]
    var sounds: [String: BundleAudio] = [:]
    var stores: [String: FileStateStore] = [:]
    var stateErrors: [String: String] = [:]
    private var blocked: Set<String> = []
    private var loops: [String: Set<String>] = [:]
    private var saved: [String: Data] = [:]
    init() {
        root = Bundle.main.bundleURL
        preview = (Bundle.main.object(forInfoDictionaryKey: "BookPreview") as? Bool) == true
        settings = preview ? PreviewSettings() : UserSettings()
        let resources = Bundle.main.resourceURL!
        let ids =
            ((try? Data(contentsOf: resources.appendingPathComponent("published-pages.json"))).flatMap {
                try? JSONDecoder().decode(Published.self, from: $0)
            })?.pages ?? []
        let data = ids.compactMap {
            try? Data(contentsOf: resources.appendingPathComponent("Pages/\($0).json"))
        }
        registry = PageRegistry(descriptors: data, published: ids)
        coordinator = BookCoordinator(
            registry: registry, source: preview ? NoAngleSource() : LidAngleSource(), clock: clock,
            settings: settings, wallClock: SystemWallClock()
        ) { [weak self] page in
            guard let self, let device = self.device else { return UnavailablePort() }
            let port = PageProcessConnection(
                service: page.service, device: device,
                restore: { [weak self] in self?.restore(page.id) ?? (nil, nil) })
            self.processes[page.id] = port
            port.onCheckpoint = { [weak self, weak port] data in
                guard let self, let port, self.processes[page.id] === port, !self.blocked.contains(page.id),
                    data != self.saved[page.id]
                else { return }
                do {
                    try self.store(page.id).save(data, previous: self.saved[page.id])
                    self.saved[page.id] = data
                    self.stateErrors[page.id] = nil
                } catch { self.stateErrors[page.id] = error.localizedDescription }
            }
            do {
                let base = self.root.appendingPathComponent(
                    "Contents/XPCServices/\(page.id).xpc/Contents/Resources")
                let assets = page.audio.map {
                    AudioAsset(
                        id: SoundID($0.id), url: base.appendingPathComponent($0.path), volume: $0.volume,
                        loops: $0.loops, autostart: $0.autostart)
                }
                self.sounds[page.id] = try BundleAudio(assets: assets)
            } catch { self.stateErrors[page.id] = error.localizedDescription }
            return port
        }
        coordinator.onScopeActive = { [weak self] id, active in
            guard let self else { return }
            self.sounds[id]?.setActive(active)
            if active { for loop in self.loops[id] ?? [] { self.sounds[id]?.startLoop(SoundID(loop)) } }
        }
        coordinator.onSounds = { [weak self] id, events in
            guard let bank = self?.sounds[id] else { return }
            for event in events {
                let sound = SoundID(event.id)
                switch event.operation {
                case .play: bank.play(sound)
                case .begin:
                    self?.loops[id, default: []].insert(event.id)
                    bank.startLoop(sound)
                case .end:
                    self?.loops[id]?.remove(event.id)
                    bank.stopLoop(sound, fade: event.fade)
                }
            }
        }
        if preview { coordinator.setFollowing(false) }
        coordinator.initialPage = lastPage()
    }
    private struct Published: Decodable {
        let version: Int
        let pages: [String]
    }
    private func store(_ id: String) throws -> FileStateStore {
        if let store = stores[id] { return store }
        let store: FileStateStore
        if preview {
            store = FileStateStore(
                url: FileManager.default.temporaryDirectory.appendingPathComponent(
                    "popupbook-preview-\(getpid())/\(id).json"))
        } else if id == "forest-cabin" {
            store = try FileStateStore.applicationStore()
        } else {
            let dir = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            store = FileStateStore(
                url: dir.appendingPathComponent("local.ssr.forestbook/pages/\(id)/state.json"))
        }
        stores[id] = store
        return store
    }
    private func restore(_ id: String) -> (Data?, Data?) {
        do {
            let storage = try store(id)
            return (try storage.load(), try storage.loadBackup())
        } catch {
            blocked.insert(id)
            stateErrors[id] = error.localizedDescription
            return (nil, nil)
        }
    }
    func saveLastPage(_ id: String) {
        guard !preview,
            let directory = try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        else { return }
        let store = FileStateStore(url: directory.appendingPathComponent("local.ssr.forestbook/book.json"))
        let data = try? JSONSerialization.data(withJSONObject: ["version": 1, "lastPage": id])
        if let data { try? store.save(data, previous: nil) }
    }
    func lastPage() -> String? {
        guard !preview,
            let directory = try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false),
            let data = try? Data(
                contentsOf: directory.appendingPathComponent("local.ssr.forestbook/book.json")),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            json["version"] as? Int == 1
        else { return nil }
        return json["lastPage"] as? String
    }
}
@MainActor private final class PreviewSettings: SettingsStore {
    var openAngle = 105.0
    var soundEnabled = false
}
@MainActor private final class NoAngleSource: AngleSource {
    func start(_ callback: @escaping @MainActor (AngleSample) -> Void) {}
    func stop() {}
}
@MainActor private final class UnavailablePort: PageProcessPort {
    var onReady: (() -> Void)?
    var onFrame: ((PagePresentation) -> Void)?
    var onFailure: ((PageError) -> Void)?
    func start(epoch: Int) { onFailure?(.missingResources) }
    func advance(_ context: WorldContext) {}
    func handle(_ input: PageInput) {}
    func pause() {}
    func stop() {}
}
