import Foundation
import PopupBookCore

/// Versioned book-level position, independent from all page-owned state schemas.
@MainActor public final class ReadingPositionStore {
    private struct Position: Codable {
        let version: Int
        let page: String
    }
    private let store: any StateStore
    private var writable = true
    private var previous: Data?
    public private(set) var lastError: String?
    public init(store: any StateStore) { self.store = store }
    private func decode(_ data: Data) throws -> Position {
        let value = try JSONDecoder().decode(Position.self, from: data)
        guard value.version == 1 else { throw StateRestoreError.unsupportedVersion(value.version) }
        guard value.page.range(of: "^[a-z][a-z0-9-]{0,63}$", options: .regularExpression) != nil else {
            throw StateRestoreError.invalidState
        }
        return value
    }
    public func load() -> String? {
        do {
            guard let data = try store.load() else { return nil }
            let position = try decode(data)
            previous = data
            return position.page
        } catch StateRestoreError.unsupportedVersion(let version) {
            writable = false
            lastError = StateRestoreError.unsupportedVersion(version).localizedDescription
            return nil
        } catch {
            if let data = try? store.loadBackup(), let restored = try? decode(data) {
                previous = data
                return restored.page
            }
            writable = false
            lastError = StateRestoreError.invalidState.localizedDescription
            return nil
        }
    }
    public func save(_ page: String) {
        guard writable else { return }
        do {
            let data = try JSONEncoder().encode(Position(version: 1, page: page))
            _ = try decode(data)
            guard data != previous else { return }
            try store.save(data, previous: previous)
            previous = data
            lastError = nil
        } catch { lastError = error.localizedDescription }
    }
}
