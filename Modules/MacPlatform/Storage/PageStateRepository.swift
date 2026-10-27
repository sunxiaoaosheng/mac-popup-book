import Foundation
import PopupBookCore

/// Page schemas are opaque. Only worker-validated checkpoints can replace files or become backups.
@MainActor public final class PageStateRepository {
    private let base: URL
    private var stores: [String: FileStateStore] = [:]
    private var previous: [String: Data] = [:]
    private var blocked: Set<String> = []
    public private(set) var errors: [String: String] = [:]
    public init(base: URL) { self.base = base }
    private func store(_ page: PageDescriptor) throws -> FileStateStore {
        try page.validate()
        if let store = stores[page.id] { return store }
        let path =
            page.legacyStateFile.map { base.appendingPathComponent($0) }
            ?? base.appendingPathComponent("pages/\(page.id)/state.json")
        let store = FileStateStore(url: path)
        stores[page.id] = store
        return store
    }
    public func restore(_ page: PageDescriptor) -> (Data?, Data?) {
        do {
            let store = try store(page)
            return (try store.load(), try store.loadBackup())
        } catch {
            blocked.insert(page.id)
            errors[page.id] = error.localizedDescription
            return (nil, nil)
        }
    }
    public func save(_ page: PageDescriptor, data: Data) {
        guard !blocked.contains(page.id), data != previous[page.id] else { return }
        do {
            guard data.count <= 1_000_000 else { throw StateRestoreError.invalidState }
            try store(page).save(data, previous: previous[page.id])
            previous[page.id] = data
            errors[page.id] = nil
        } catch { errors[page.id] = error.localizedDescription }
    }
}
