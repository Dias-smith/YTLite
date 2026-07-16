import Foundation
import SwiftUI

/// Runtime language override. Catalog lookup must use the matching `.lproj` bundle —
/// `String(localized:locale:)` still follows system preferred languages.
enum AppLocalization {
    /// BCP-47 code used for `xx.lproj` lookup (`en`, `zh-Hans`, `pt-BR`, …).
    nonisolated(unsafe) static var languageCode: String = "en"

    nonisolated(unsafe) static var locale: Locale = Locale(identifier: "en")

    static var stringsBundle: Bundle {
        if let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
           let bundle = Bundle(path: path)
        {
            return bundle
        }
        // Fallback: try language without region (e.g. `pt` if `pt-BR` missing).
        let base = languageCode.split(separator: "-").first.map(String.init) ?? languageCode
        if base != languageCode,
           let path = Bundle.main.path(forResource: base, ofType: "lproj"),
           let bundle = Bundle(path: path)
        {
            return bundle
        }
        return .main
    }

    static func apply(_ language: AppLanguage) {
        let resolved = language.locale
        locale = resolved
        let code: String
        switch language {
        case .system:
            // `Locale.identifier` may use underscores (`zh_Hans`); lproj uses hyphens.
            code = resolved.identifier.replacingOccurrences(of: "_", with: "-")
        default:
            code = language.rawValue
        }
        languageCode = Self.normalizeLanguageCode(code)
    }

    /// Map locale identifiers onto folder names that exist in the app bundle.
    private static func normalizeLanguageCode(_ code: String) -> String {
        let lowered = code.replacingOccurrences(of: "_", with: "-")
        if lowered.lowercased().hasPrefix("zh-hant")
            || lowered.lowercased().hasPrefix("zh-tw")
            || lowered.lowercased().hasPrefix("zh-hk")
            || lowered.lowercased().hasPrefix("zh-mo")
        {
            return "zh-Hant"
        }
        if lowered.lowercased().hasPrefix("zh") { return "zh-Hans" }
        if lowered.lowercased().hasPrefix("pt") { return "pt-BR" }
        for supported in ["en", "es", "ar", "fr", "hi", "pt-BR", "zh-Hans", "zh-Hant"] {
            if lowered.caseInsensitiveCompare(supported) == .orderedSame {
                return supported
            }
        }
        let base = lowered.split(separator: "-").first.map(String.init) ?? lowered
        for supported in ["en", "es", "ar", "fr", "hi"] {
            if base.caseInsensitiveCompare(supported) == .orderedSame {
                return supported
            }
        }
        return "en"
    }
}

/// App language preference tags (Settings). `system` follows the device.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case en
    case ptBR = "pt-BR"
    case es
    case ar
    case fr
    case hi
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"

    var id: String { rawValue }

    /// Native / endonym label for the Settings picker (not localized via Catalog).
    var displayName: String {
        switch self {
        case .system: return L("lang.system")
        case .en: return "English"
        case .ptBR: return "Português (Brasil)"
        case .es: return "Español"
        case .ar: return "العربية"
        case .fr: return "Français"
        case .hi: return "हिन्दी"
        case .zhHans: return "中文（简体）"
        case .zhHant: return "中文（繁體）"
        }
    }

    var isRTL: Bool { self == .ar }

    var locale: Locale {
        switch self {
        case .system:
            return Self.resolveSystemLocale()
        case .en:
            return Locale(identifier: "en")
        case .ptBR:
            return Locale(identifier: "pt-BR")
        case .es:
            return Locale(identifier: "es")
        case .ar:
            return Locale(identifier: "ar")
        case .fr:
            return Locale(identifier: "fr")
        case .hi:
            return Locale(identifier: "hi")
        case .zhHans:
            return Locale(identifier: "zh-Hans")
        case .zhHant:
            return Locale(identifier: "zh-Hant")
        }
    }

    static func migrateStoredCode(_ raw: String) -> String {
        switch raw {
        case "zh": return AppLanguage.zhHans.rawValue
        case "pt": return AppLanguage.ptBR.rawValue
        default: return raw
        }
    }

    static func fromStored(_ raw: String) -> AppLanguage {
        let migrated = migrateStoredCode(raw)
        return AppLanguage(rawValue: migrated) ?? .system
    }

    /// Map device preferred language → a supported app language (fallback `en`).
    static func resolveSystemLocale() -> Locale {
        for preferred in Locale.preferredLanguages {
            let id = preferred.lowercased()
            if id.hasPrefix("zh-hant") || id.hasPrefix("zh-tw") || id.hasPrefix("zh-hk") || id.hasPrefix("zh-mo") {
                return Locale(identifier: "zh-Hant")
            }
            if id.hasPrefix("zh") {
                return Locale(identifier: "zh-Hans")
            }
            if id.hasPrefix("pt") {
                return Locale(identifier: "pt-BR")
            }
            if id.hasPrefix("es") { return Locale(identifier: "es") }
            if id.hasPrefix("ar") { return Locale(identifier: "ar") }
            if id.hasPrefix("fr") { return Locale(identifier: "fr") }
            if id.hasPrefix("hi") { return Locale(identifier: "hi") }
            if id.hasPrefix("en") { return Locale(identifier: "en") }
        }
        return Locale(identifier: "en")
    }
}

/// Look up a key in the active language's `Localizable.strings` (compiled from String Catalog).
func L(_ key: String) -> String {
    AppLocalization.stringsBundle.localizedString(forKey: key, value: key, table: "Localizable")
}

/// Format strings that use `%d` / `%@` placeholders in the catalog.
func Lf(_ key: String, _ arguments: CVarArg...) -> String {
    let format = L(key)
    return String(format: format, locale: AppLocalization.locale, arguments: arguments)
}
