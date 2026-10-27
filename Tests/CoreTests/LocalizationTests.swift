import Foundation
import PopupBookCore
import XCTest

final class LocalizationTests: XCTestCase {
    func testLanguagePriorityFallbackAndFormattedValues() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for (language, value) in [("en", "Open %@%%"), ("zh-Hans", "展开 %@%%")] {
            let folder = root.appendingPathComponent("\(language).lproj")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let strings = ["progress": value]
            let data = try PropertyListSerialization.data(fromPropertyList: strings, format: .xml, options: 0)
            try data.write(to: folder.appendingPathComponent("Localizable.strings"))
        }
        let bundle = try XCTUnwrap(Bundle(path: root.path))
        func text(_ languages: [String]) -> String {
            LocalizedText.string("progress", bundle: bundle, languages: languages, arguments: ["85"])
        }
        XCTAssertEqual(text(["en-US"]), "Open 85%")
        XCTAssertEqual(text(["zh-Hans-CN"]), "展开 85%")
        XCTAssertEqual(text(["ja-JP"]), "Open 85%")
        XCTAssertEqual(text(["fr-FR", "zh-Hans"]), "展开 85%")
        XCTAssertEqual(text(["en-GB", "zh-Hans"]), "Open 85%")
        XCTAssertEqual(LocalizedText.string("missing", bundle: bundle, languages: ["en"]), "missing")
    }
}
