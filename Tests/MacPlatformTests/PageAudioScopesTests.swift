import MacPlatform
import PopupBookCore
import XCTest

@MainActor private final class AudioSpy: AudioOutput {
    var lastError: String?
    var active = false
    var played: [String] = []
    var sounding: Set<String> = []
    func setActive(_ active: Bool) {
        self.active = active
        if !active { sounding = [] }
    }
    func play(_ sound: SoundID) { if active { played.append(sound.rawValue) } }
    func startLoop(_ sound: SoundID) { if active { sounding.insert(sound.rawValue) } }
    func stopLoop(_ sound: SoundID, fade: Double) { sounding.remove(sound.rawValue) }
}
@MainActor final class PageAudioScopesTests: XCTestCase {
    func testMuteResumeLoopAndRetiredPageCannotAffectOtherPage() {
        let scopes = PageAudioScopes()
        let a = AudioSpy()
        let b = AudioSpy()
        scopes.register("a", bank: a)
        scopes.register("b", bank: b)
        scopes.setActive("a", true)
        scopes.consume("a", commands: [PageSound("loop", .begin)])
        XCTAssertEqual(a.sounding, ["loop"])
        scopes.setActive("a", false)
        XCTAssertTrue(a.sounding.isEmpty)
        scopes.consume("a", commands: [PageSound("tap", .play)])
        XCTAssertTrue(a.played.isEmpty)
        scopes.setActive("a", true)
        XCTAssertEqual(a.sounding, ["loop"])
        scopes.remove("a")
        scopes.setActive("b", true)
        scopes.consume("a", commands: [PageSound("loop", .begin)])
        XCTAssertTrue(a.sounding.isEmpty)
        XCTAssertTrue(b.sounding.isEmpty)
        scopes.consume("b", commands: [PageSound("tick", .play)])
        XCTAssertEqual(b.played, ["tick"])
    }
}
