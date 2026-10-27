import Foundation

/// Storage knows bytes and atomic replacement, never a particular character's schema.
@MainActor public protocol StateStore: AnyObject {
    func load() throws -> Data?
    func loadBackup() throws -> Data?
    func save(_ data: Data, previous: Data?) throws
}

public enum StateRestoreError: Error, LocalizedError {
    case unsupportedVersion(Int)
    case invalidState
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return L10n.text("不支持存档版本 %@，已保护原文件，请使用兼容版本打开。", String(version))
        case .invalidState: return L10n.text("存档内容不完整，原文件已保留。")
        }
    }
}

@MainActor public protocol WallClock: AnyObject { var date: Date { get } }
