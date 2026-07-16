import Foundation
import Combine
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var nightModeEnabled: Bool {
        didSet { UserDefaults.standard.set(nightModeEnabled, forKey: "night_mode_enabled") }
    }
    @Published var languageCode: String {
        didSet {
            // Persist migrated code only — do not reassign `languageCode` here (would recurse).
            let migrated = AppLanguage.migrateStoredCode(languageCode)
            UserDefaults.standard.set(migrated, forKey: "app_language")
            AppLocalization.apply(AppLanguage.fromStored(migrated))
        }
    }
    @Published var isAuthenticated: Bool = false
    /// Bumped after library sync / account-switch adopt so Subs & Library reload.
    @Published private(set) var libraryRevision: Int = 0
    /// True after login / logout / account switch until library bucket sync finishes.
    @Published private(set) var isLibrarySyncing: Bool = false

    let config = AppConfig.fromBundle()

    var appLanguage: AppLanguage {
        AppLanguage.fromStored(languageCode)
    }

    var resolvedLocale: Locale {
        appLanguage.locale
    }

    var layoutDirection: LayoutDirection {
        appLanguage.isRTL ? .rightToLeft : .leftToRight
    }

    init() {
        nightModeEnabled = UserDefaults.standard.object(forKey: "night_mode_enabled") as? Bool ?? true
        let stored = UserDefaults.standard.string(forKey: "app_language") ?? AppLanguage.system.rawValue
        let migrated = AppLanguage.migrateStoredCode(stored)
        languageCode = migrated
        if migrated != stored {
            UserDefaults.standard.set(migrated, forKey: "app_language")
        }
        AppLocalization.apply(AppLanguage.fromStored(migrated))
        UserDefaults.standard.removeObject(forKey: "wifi_only")
        UserDefaults.standard.removeObject(forKey: "resume_enabled")
        UserDefaults.standard.removeObject(forKey: "thread_count")
        UserDefaults.standard.removeObject(forKey: "default_format")
    }

    func syncAuth(_ auth: AuthService) {
        isAuthenticated = auth.isAuthenticated
    }

    func bumpLibraryRevision() {
        libraryRevision += 1
    }

    func beginLibrarySync() {
        isLibrarySyncing = true
    }

    func endLibrarySync() {
        isLibrarySyncing = false
        libraryRevision += 1
    }
}

struct AppConfig: Sendable {
    var supabaseURL: String
    var supabaseAnonKey: String
    var googleClientID: String
    var youtubeDataAPIKey: String

    static func fromBundle() -> AppConfig {
        let info = Bundle.main.infoDictionary ?? [:]
        return AppConfig(
            supabaseURL: info["SUPABASE_URL"] as? String ?? "",
            supabaseAnonKey: info["SUPABASE_ANON_KEY"] as? String ?? "",
            googleClientID: info["GOOGLE_CLIENT_ID"] as? String ?? "",
            youtubeDataAPIKey: info["YOUTUBE_DATA_API_KEY"] as? String ?? ""
        )
    }

    var isConfigured: Bool {
        !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty
    }
}
