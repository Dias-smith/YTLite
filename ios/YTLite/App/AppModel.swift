import Foundation
import Combine
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    /// Theme selection is owned by `ThemeStore` (persisted). Forward revision for view rebuilds.
    var themeStore: ThemeStore { ThemeStore.shared }

    var themeColorScheme: ColorScheme { themeStore.colorScheme }
    var themeRevision: Int { themeStore.themeRevision }
    var themeDisplayName: String { themeStore.activeDisplayName }

    @Published var languageCode: String {
        didSet {
            // Persist migrated code only — do not reassign `languageCode` here (would recurse).
            let migrated = AppLanguage.migrateStoredCode(languageCode)
            UserDefaults.standard.set(migrated, forKey: "app_language")
            AppLocalization.apply(AppLanguage.fromStored(migrated))
            applyCatalogContentLocaleIfNeeded()
        }
    }

    @Published var contentRegionCode: String {
        didSet {
            UserDefaults.standard.set(contentRegionCode, forKey: AppContentLocale.contentRegionKey)
            applyCatalogContentLocaleIfNeeded()
        }
    }

    /// When false, hide PiP controls and block starting Picture in Picture.
    @Published var pictureInPictureEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(pictureInPictureEnabled, forKey: Self.pictureInPictureKey)
            guard !isHydratingStoredPreferences else { return }
            NotificationCenter.default.post(name: .ytlitePictureInPictureSettingDidChange, object: nil)
        }
    }

    /// Bumped when InnerTube `hl` / `gl` changes so feeds can reload.
    @Published private(set) var contentLocaleRevision: Int = 0
    /// Blocks home feed until first-launch locale sheet is confirmed.
    @Published private(set) var isAwaitingLocaleSetup: Bool = false
    @Published var showLocaleSetupSheet: Bool = false
    @Published var isAuthenticated: Bool = false
    /// Bumped after library sync / account-switch adopt so Subs & Library reload.
    @Published private(set) var libraryRevision: Int = 0
    /// True after login / logout / account switch until library bucket sync finishes.
    @Published private(set) var isLibrarySyncing: Bool = false
    /// When the current library sync began (for collapsing the modal after 5s).
    private(set) var librarySyncStartedAt: Date?

    let config = AppConfig.fromBundle()

    private var themeCancellable: AnyCancellable?
    private var isHydratingStoredPreferences = false

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
        // Hydrate themes before any view reads YTLiteColor.
        _ = ThemeStore.shared

        let stored = UserDefaults.standard.string(forKey: "app_language") ?? AppLanguage.system.rawValue
        let migrated = AppLanguage.migrateStoredCode(stored)
        isHydratingStoredPreferences = true
        languageCode = migrated
        if migrated != stored {
            UserDefaults.standard.set(migrated, forKey: "app_language")
        }
        AppLocalization.apply(AppLanguage.fromStored(migrated))

        let storedRegion = UserDefaults.standard.string(forKey: AppContentLocale.contentRegionKey)
        contentRegionCode = AppContentRegion.fromStored(storedRegion).rawValue
        if storedRegion == nil {
            UserDefaults.standard.set(contentRegionCode, forKey: AppContentLocale.contentRegionKey)
        }
        if UserDefaults.standard.object(forKey: Self.pictureInPictureKey) != nil {
            pictureInPictureEnabled = UserDefaults.standard.bool(forKey: Self.pictureInPictureKey)
        }
        isHydratingStoredPreferences = false
        _ = AppContentLocale.syncCatalogFromAppLanguage(appLanguage, regionCode: contentRegionCode)

        if AppContentLocale.shouldPresentLocaleSetupOnLaunch {
            isAwaitingLocaleSetup = true
            showLocaleSetupSheet = true
        }

        UserDefaults.standard.removeObject(forKey: "wifi_only")
        UserDefaults.standard.removeObject(forKey: "resume_enabled")
        UserDefaults.standard.removeObject(forKey: "thread_count")
        UserDefaults.standard.removeObject(forKey: "default_format")

        themeCancellable = ThemeStore.shared.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func selectTheme(id: String) {
        themeStore.select(themeId: id)
    }

    func syncAuth(_ auth: AuthService) {
        isAuthenticated = auth.isAuthenticated
    }

    func bumpLibraryRevision() {
        libraryRevision += 1
    }

    func beginLibrarySync() {
        if !isLibrarySyncing {
            librarySyncStartedAt = Date()
        }
        isLibrarySyncing = true
    }

    func endLibrarySync() {
        isLibrarySyncing = false
        librarySyncStartedAt = nil
        libraryRevision += 1
    }

    var appContentRegion: AppContentRegion {
        AppContentRegion.fromStored(contentRegionCode)
    }

    func completeLocaleSetup(languageCode: String, regionCode: String) {
        isHydratingStoredPreferences = true
        let migrated = AppLanguage.migrateStoredCode(languageCode)
        self.languageCode = migrated
        contentRegionCode = regionCode.uppercased()
        isHydratingStoredPreferences = false
        #if !DEBUG
        UserDefaults.standard.set(true, forKey: AppContentLocale.localeSetupCompletedKey)
        #endif
        _ = AppContentLocale.syncCatalogFromAppLanguage(appLanguage, regionCode: contentRegionCode)
        contentLocaleRevision += 1
        HomeFeedStore.invalidateMemoryCache()
        InnerTubeClient.invalidateHotKeywordsCache()
        isAwaitingLocaleSetup = false
        showLocaleSetupSheet = false
    }

    private func applyCatalogContentLocaleIfNeeded() {
        guard !isHydratingStoredPreferences else { return }
        let changed = AppContentLocale.syncCatalogFromAppLanguage(appLanguage, regionCode: contentRegionCode)
        guard changed else { return }
        contentLocaleRevision += 1
        HomeFeedStore.invalidateMemoryCache()
        InnerTubeClient.invalidateHotKeywordsCache()
    }

    private static let pictureInPictureKey = PictureInPictureSettings.defaultsKey
}

struct AppConfig: Sendable {
    var supabaseURL: String
    var supabaseAnonKey: String
    var googleClientID: String
    var catalogDataAPIKey: String

    static func fromBundle() -> AppConfig {
        let info = Bundle.main.infoDictionary ?? [:]
        return AppConfig(
            supabaseURL: info["SUPABASE_URL"] as? String ?? "",
            supabaseAnonKey: info["SUPABASE_ANON_KEY"] as? String ?? "",
            googleClientID: info["GOOGLE_CLIENT_ID"] as? String ?? "",
            catalogDataAPIKey: info[SaltedLiteral.infoCatalogDataApiKey] as? String ?? ""
        )
    }

    var isConfigured: Bool {
        !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty
    }
}
