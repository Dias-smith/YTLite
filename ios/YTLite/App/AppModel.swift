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

    let config = AppConfig.fromBundle()

    init() {
        nightModeEnabled = UserDefaults.standard.object(forKey: "night_mode_enabled") as? Bool ?? true
        languageCode = UserDefaults.standard.string(forKey: "app_language") ?? "system"
        UserDefaults.standard.removeObject(forKey: "wifi_only")
        UserDefaults.standard.removeObject(forKey: "resume_enabled")
        UserDefaults.standard.removeObject(forKey: "thread_count")
        UserDefaults.standard.removeObject(forKey: "default_format")
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
