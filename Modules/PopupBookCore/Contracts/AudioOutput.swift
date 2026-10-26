import Foundation

@MainActor public protocol AudioOutput: AnyObject {
    var lastError: String? { get }
    func setActive(_ active: Bool)
    func play(_ sound: SoundID)
}
