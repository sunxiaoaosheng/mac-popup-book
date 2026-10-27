import Foundation
import PopupBookCore

@MainActor public final class FileStateStore: StateStore {
    private let url: URL
    private var backupURL: URL { url.appendingPathExtension("backup") }
    public init(url: URL) { self.url = url }
    public static func applicationStore() throws -> FileStateStore {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        return FileStateStore(
            url: directory.appendingPathComponent("local.ssr.forestbook", isDirectory: true)
                .appendingPathComponent("resident.json"))
    }
    public func load() throws -> Data? { try read(url) }
    public func loadBackup() throws -> Data? { try read(backupURL) }
    private func read(_ path: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        return try Data(contentsOf: path)
    }
    public func save(_ data: Data, previous: Data?) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // The caller supplies only a validated snapshot, never the possibly corrupt primary file.
        if let previous { try previous.write(to: backupURL, options: .atomic) }
        try data.write(to: url, options: .atomic)
    }
}

@MainActor public final class SystemWallClock: WallClock {
    public init() {}
    public var date: Date { Date() }
}
