import Foundation

@MainActor public protocol AudioOutput: AnyObject {
    var lastError: String? { get }
    func setActive(_ active: Bool)
    func play(_ sound: SoundID)
    func startLoop(_ sound: SoundID)
    func stopLoop(_ sound: SoundID, fade: Double)
}

extension AudioOutput {
    public func startLoop(_ sound: SoundID) {}
    public func stopLoop(_ sound: SoundID, fade: Double) {}
}
