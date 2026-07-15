import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var nightModeEnabled: Bool {
        didSet { UserDefaults.standard.set(nightModeEnabled, forKey: "night_mode_enabled") }
    }
    @Published var languageCode: String {
        didSet { UserDefaults.standard.set(languageCode, forKey: "app_language") }
    }
    @Published var isAuthenticated: Bool = false
    @Published var downloadWifiOnly: Bool {
        didSet { UserDefaults.standard.set(downloadWifiOnly, forKey: "wifi_only") }
    }
    @Published var downloadResumeEnabled: Bool {
        didSet { UserDefaults.standard.set(downloadResumeEnabled, forKey: "resume_enabled") }
    }
    @Published var downloadThreadCount: Int {
        didSet { UserDefaults.standard.set(downloadThreadCount, forKey: "thread_count") }
    }

    let config = AppConfig.fromBundle()

    init() {
        nightModeEnabled = UserDefaults.standard.object(forKey: "night_mode_enabled") as? Bool ?? true
        languageCode = UserDefaults.standard.string(forKey: "app_language") ?? "system"
        downloadWifiOnly = UserDefaults.standard.bool(forKey: "wifi_only")
        downloadResumeEnabled = UserDefaults.standard.object(forKey: "resume_enabled") as? Bool ?? true
        downloadThreadCount = UserDefaults.standard.object(forKey: "thread_count") as? Int ?? 2
    }

    func syncAuth(_ auth: AuthService) {
        isAuthenticated = auth.isAuthenticated
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
