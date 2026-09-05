import Foundation

/// Watch string catalog lookup (`Localizable.xcstrings` in the Watch target).
enum WatchL10n {
    static func string(_ key: String, default defaultValue: String) -> String {
        let value = Bundle.main.localizedString(forKey: key, value: defaultValue, table: "Localizable")
        return value.isEmpty ? defaultValue : value
    }
}

func WL(_ key: String, _ defaultValue: String) -> String {
    WatchL10n.string(key, default: defaultValue)
}
