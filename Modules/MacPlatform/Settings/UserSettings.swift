import AppKit
import PopupBookCore

@MainActor public final class UserSettings: SettingsStore {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public var openAngle: Double {
        get {
            let value = defaults.double(forKey: "forest.openAngle")
            return (80...120).contains(value) ? value : 105
        }
        set { if (80...120).contains(newValue) { defaults.set(newValue, forKey: "forest.openAngle") } }
    }
    public var soundEnabled: Bool {
        get { defaults.bool(forKey: "forest.sound") }
        set { defaults.set(newValue, forKey: "forest.sound") }
    }
}
