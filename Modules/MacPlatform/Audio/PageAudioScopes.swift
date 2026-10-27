import Foundation
import PopupBookCore

/// Sound effects and desired loops belong to a page scope, not the process connection lifetime.
@MainActor public final class PageAudioScopes {
    private var banks: [String: any AudioOutput] = [:]
    private var loops: [String: Set<String>] = [:]
    private var errors: [String: String] = [:]
    public init() {}
    public func register(_ page: String, bank: any AudioOutput) {
        remove(page)
        banks[page] = bank
    }
    public func reportFailure(_ page: String, message: String) { errors[page] = message }
    public func error(for page: String) -> String? { errors[page] }
    public func setActive(_ page: String, _ active: Bool) {
        guard let bank = banks[page] else { return }
        bank.setActive(active)
        if active { for loop in loops[page] ?? [] { bank.startLoop(SoundID(loop)) } }
        errors[page] = bank.lastError
    }
    public func consume(_ page: String, commands: [PageSound]) {
        guard let bank = banks[page] else { return }
        for command in commands {
            let id = SoundID(command.id)
            switch command.operation {
            case .play: bank.play(id)
            case .begin:
                loops[page, default: []].insert(command.id)
                bank.startLoop(id)
            case .end:
                loops[page]?.remove(command.id)
                bank.stopLoop(id, fade: command.fade)
            }
        }
        errors[page] = bank.lastError
    }
    public func remove(_ page: String) {
        banks[page]?.setActive(false)
        banks[page] = nil
        loops[page] = nil
        errors[page] = nil
    }
}
