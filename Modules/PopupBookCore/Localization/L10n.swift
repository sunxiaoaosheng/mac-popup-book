import Foundation

enum L10n {
    static func text(_ key: String, _ arguments: String...) -> String {
        LocalizedText.string(key, bundle: .module, arguments: arguments)
    }
}
