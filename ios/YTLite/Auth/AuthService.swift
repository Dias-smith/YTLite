import Foundation
import Supabase
import AuthenticationServices

@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var session: Session?
    @Published private(set) var isBusy = false
    @Published var lastError: String?

    private var client: SupabaseClient?

    var isAuthenticated: Bool { session != nil }
    var userId: String? { session?.user.id.uuidString.lowercased() }
    var isConfigured: Bool { client != nil }

    init(config: AppConfig) {
        guard config.isConfigured,
              let url = URL(string: config.supabaseURL)
        else { return }
        client = SupabaseClient(supabaseURL: url, supabaseKey: config.supabaseAnonKey)
        Task { await refreshSession() }
    }

    func refreshSession() async {
        guard let client else { return }
        do {
            session = try await client.auth.session
        } catch {
            session = nil
        }
    }

    func signInWithGoogle() async {
        guard let client else {
            lastError = "Supabase is not configured. Fill ios/Config/Secrets.xcconfig.local"
            return
        }
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            try await client.auth.signInWithOAuth(
                provider: .google,
                redirectTo: URL(string: "ytlite://auth-callback")
            ) { (session: ASWebAuthenticationSession) in
                session.prefersEphemeralWebBrowserSession = false
            }
            session = try await client.auth.session
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signOut() async {
        guard let client else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await client.auth.signOut()
            session = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func supabaseClient() -> SupabaseClient? { client }
}
