import Foundation

@MainActor public protocol SettingsStore: AnyObject {
    var openAngle: Double { get set }
    var soundEnabled: Bool { get set }
}
