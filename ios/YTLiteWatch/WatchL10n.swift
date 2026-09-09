import Foundation

/// Watch string catalog lookup (`Localizable.xcstrings` in the Watch target).
enum WatchL10n {
    /// Call once at process start. DEBUG forces English regardless of Watch system language.
    static func configureAtLaunch() {
        #if DEBUG
        UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        #endif
    }

    static func string(_ key: String, default defaultValue: String) -> String {
        let value = Bundle.main.localizedString(forKey: key, value: defaultValue, table: "Localizable")
        return value.isEmpty ? defaultValue : value
    }
}

func WL(_ key: String, _ defaultValue: String) -> String {
    WatchL10n.string(key, default: defaultValue)
}
