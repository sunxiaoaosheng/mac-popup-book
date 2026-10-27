import Foundation
import MacPlatform
import XCTest

@MainActor final class StateStoreTests: XCTestCase {
    func testAtomicReplacementKeepsCallerValidatedBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("state.json")
        let store = FileStateStore(url: path)
        XCTAssertNil(try store.load())
        let first = Data("first".utf8)
        let second = Data("second".utf8)
        try store.save(first, previous: nil)
        try store.save(second, previous: first)
        XCTAssertEqual(try store.load(), second)
        XCTAssertEqual(try store.loadBackup(), first)
        try Data("corrupt".utf8).write(to: path)
        // A recovered caller never asks storage to back up unvalidated primary bytes.
        try store.save(second, previous: first)
        XCTAssertEqual(try store.loadBackup(), first)
        XCTAssertEqual(try store.load(), second)
    }
}
