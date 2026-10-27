import Foundation
import MacPlatform
import Metal
import PopupBookCore
import PopupBookRuntime

extension PageProcessConnection: PageProcessPort {}

@MainActor final class HostComposition {
    let clock = DisplayFrameClock()
    private let supervisor = PageProcessSupervisor()
    let settings: any SettingsStore
    let registry: PageRegistry
    let device = MTLCreateSystemDefaultDevice()
    let preview: Bool
    let root: URL
    var coordinator: BookCoordinator!
    var processes: [String: PageProcessConnection] = [:]
    let audio = PageAudioScopes()
    var stateErrors: [String: String] = [:]
    private var pageStates: PageStateRepository?
    private var position: ReadingPositionStore?
    init() {
        root = Bundle.main.bundleURL
        preview = (Bundle.main.object(forInfoDictionaryKey: "BookPreview") as? Bool) == true
        settings = preview ? PreviewSettings() : UserSettings()
        let resources = Bundle.main.resourceURL ?? root.appendingPathComponent("Contents/Resources")
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
                service: page.service, device: device, supervisor: self.supervisor,
                expectedPath: self.root.appendingPathComponent(
                    "Contents/XPCServices/\(page.id).xpc/Contents/MacOS/\(page.product)"
                ).path,
                restore: { [weak self] in self?.stateRepository()?.restore(page) ?? (nil, nil) })
            self.processes[page.id] = port
            port.onCheckpoint = { [weak self, weak port] data in
                guard let self, let port, self.processes[page.id] === port else { return }
                self.stateRepository()?.save(page, data: data)
            }
            do {
                let base = self.root.appendingPathComponent(
                    "Contents/XPCServices/\(page.id).xpc/Contents/Resources")
                let assets = page.audio.map {
                    AudioAsset(
                        id: SoundID($0.id), url: base.appendingPathComponent($0.path), volume: $0.volume,
                        loops: $0.loops, autostart: $0.autostart)
                }
                self.audio.register(page.id, bank: try BundleAudio(assets: assets))
            } catch { self.audio.reportFailure(page.id, message: error.localizedDescription) }
            return port
        }
        coordinator.onScopeEnded = { [weak self] id in self?.audio.remove(id) }
        coordinator.onScopeActive = { [weak self] id, active in self?.audio.setActive(id, active) }
        coordinator.onSounds = { [weak self] id, events in self?.audio.consume(id, commands: events) }
        if preview { coordinator.setFollowing(false) }
        coordinator.initialPage = lastPage()
    }
    private struct Published: Decodable {
        let version: Int
        let pages: [String]
    }
    private func stateRepository() -> PageStateRepository? {
        if let pageStates { return pageStates }
        do {
            let base: URL
            if preview {
                base = FileManager.default.temporaryDirectory.appendingPathComponent(
                    "popupbook-preview-\(getpid())")
            } else {
                base = try FileManager.default.url(
                    for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
                ).appendingPathComponent("local.ssr.forestbook")
            }
            let repository = PageStateRepository(base: base)
            pageStates = repository
            return repository
        } catch {
            stateErrors["book"] = error.localizedDescription
            return nil
        }
    }
    func pageError(_ id: String) -> String? {
        audio.error(for: id) ?? pageStates?.errors[id] ?? stateErrors[id]
    }
    func shutdown() {
        coordinator.stop()
        let supervisor = self.supervisor
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { supervisor.shutdown() }
    }
    private func positionStore() -> ReadingPositionStore? {
        if let position { return position }
        guard !preview else { return nil }
        do {
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let store = ReadingPositionStore(
                store: FileStateStore(url: directory.appendingPathComponent("local.ssr.forestbook/book.json"))
            )
            position = store
            return store
        } catch {
            stateErrors["book"] = error.localizedDescription
            return nil
        }
    }
    func saveLastPage(_ id: String) {
        let store = positionStore()
        store?.save(id)
        stateErrors["book"] = store?.lastError
    }
    func lastPage() -> String? {
        let store = positionStore()
        let id = store?.load()
        stateErrors["book"] = store?.lastError
        return id
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
