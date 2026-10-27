import Foundation

/// Resolves a module's own catalog using macOS language preferences, with English fallback.
/// Callers own their content; this helper has no scene or character vocabulary.
public enum LocalizedText {
    private static let catalogs = NSCache<NSString, Bundle>()
    public static func string(
        _ key: String, bundle: Bundle, languages: [String] = Locale.preferredLanguages,
        arguments: [String] = []
    ) -> String {
        let available = ["en", "zh-Hans"]
        let language = Bundle.preferredLocalizations(from: available, forPreferences: languages).first ?? "en"
        let selected = language == "zh-Hans" ? "zh-Hans" : "en"
        let cacheKey = "\(bundle.bundleURL.path)|\(selected)" as NSString
        let catalog: Bundle
        if let cached = catalogs.object(forKey: cacheKey) {
            catalog = cached
        } else {
            guard let path = bundle.path(forResource: selected, ofType: "lproj"),
                let loaded = Bundle(path: path)
            else { return key }
            catalogs.setObject(loaded, forKey: cacheKey)
            catalog = loaded
        }
        let format = catalog.localizedString(forKey: key, value: key, table: nil)
        return arguments.isEmpty ? format : String(format: format, arguments: arguments)
    }
}
