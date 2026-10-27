import Foundation
import MacPlatform
import XCTest

@MainActor final class ReadingPositionTests: XCTestCase {
    func testFuturePositionCannotBeOverwritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = FileStateStore(url: root.appendingPathComponent("book.json"))
        let data = Data("{\"version\":9,\"page\":\"future\"}".utf8)
        try storage.save(data, previous: nil)
        let position = ReadingPositionStore(store: storage)
        XCTAssertNil(position.load())
        XCTAssertNotNil(position.lastError)
        position.save("forest-cabin")
        XCTAssertEqual(try storage.load(), data)
    }
    func testValidBackupRecoveryAndSubsequentSave() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = FileStateStore(url: root.appendingPathComponent("book.json"))
        let valid = Data("{\"version\":1,\"page\":\"first\"}".utf8)
        try storage.save(Data("bad".utf8), previous: valid)
        let position = ReadingPositionStore(store: storage)
        XCTAssertEqual(position.load(), "first")
        position.save("second")
        XCTAssertEqual(ReadingPositionStore(store: storage).load(), "second")
        XCTAssertEqual(try storage.loadBackup(), valid)
    }
}
