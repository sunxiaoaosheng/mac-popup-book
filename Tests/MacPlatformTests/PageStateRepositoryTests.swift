import Foundation
import MacPlatform
import PopupBookCore
import XCTest

@MainActor final class PageStateRepositoryTests: XCTestCase {
    private func page(_ id: String, legacy: String? = nil) throws -> PageDescriptor {
        var object: [String: Any] = [
            "id": id, "order": 0, "names": ["en": id, "zh-Hans": id], "contractVersion": 1,
            "service": "local.test." + id, "product": "Worker", "audio": [],
        ]
        if let legacy { object["legacyStateFile"] = legacy }
        return try JSONDecoder().decode(
            PageDescriptor.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func testLegacyMappingAndTwoPagesNeverShareSnapshots() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = PageStateRepository(base: root)
        let a = try page("first", legacy: "resident.json")
        let b = try page("second")
        XCTAssertNil(repository.restore(a).0)
        XCTAssertNil(repository.restore(b).0)
        repository.save(a, data: Data([1]))
        repository.save(b, data: Data([9]))
        repository.save(a, data: Data([2]))
        XCTAssertEqual(repository.restore(a).0, Data([2]))
        XCTAssertEqual(repository.restore(a).1, Data([1]))
        XCTAssertEqual(repository.restore(b).0, Data([9]))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("resident.json")), Data([2]))
    }
    func testInvalidLegacyPathIsBlockedWithoutAffectingAnotherPage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = PageStateRepository(base: root.appendingPathComponent("base"))
        let bad = try page("bad", legacy: "../escaped.json")
        let good = try page("good")
        XCTAssertNil(repository.restore(bad).0)
        repository.save(bad, data: Data([1]))
        XCTAssertNotNil(repository.errors["bad"])
        repository.save(good, data: Data([2]))
        XCTAssertEqual(repository.restore(good).0, Data([2]))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("escaped.json").path))
    }
}
