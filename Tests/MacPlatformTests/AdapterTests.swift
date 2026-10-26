import Foundation
import MacPlatform
import XCTest

@MainActor final class AdapterTests: XCTestCase {
    func testExistingSettingsKeysAndIsolatedWrites() throws {
        let suite = "local.popup-book.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(96.0, forKey: "forest.openAngle")
        defaults.set(true, forKey: "forest.sound")
        let settings = UserSettings(defaults: defaults)
        XCTAssertEqual(settings.openAngle, 96)
        XCTAssertTrue(settings.soundEnabled)
        settings.openAngle = 115
        settings.soundEnabled = false
        XCTAssertEqual(defaults.double(forKey: "forest.openAngle"), 115)
        XCTAssertFalse(defaults.bool(forKey: "forest.sound"))
        settings.openAngle = 40
        XCTAssertEqual(settings.openAngle, 115)
    }
    func testSensorReportDecodeWithoutOpeningDevice() {
        XCTAssertEqual(LidAngleSource.decode([1, 103, 0]), 103)
        XCTAssertNil(LidAngleSource.decode([1, 0]))
        XCTAssertNil(LidAngleSource.decode([2, 90, 0]))
        XCTAssertNil(LidAngleSource.decode([1, 255, 255]))
    }
}
