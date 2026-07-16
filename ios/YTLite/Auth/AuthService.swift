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

    /// Google profile name for You / Library headers.
    var displayName: String {
        if let name = metaString("full_name") ?? metaString("name"), !name.isEmpty {
            return name
        }
        if let email = session?.user.email, !email.isEmpty {
            return email.split(separator: "@").first.map(String.init) ?? email
        }
        return "Account"
    }

    var emailHandle: String? {
        session?.user.email
    }

    var avatarURL: URL? {
        (metaString("avatar_url") ?? metaString("picture")).flatMap(URL.init(string:))
    }

    init(config: AppConfig) {
        guard config.isConfigured,
              let url = URL(string: config.supabaseURL)
        else { return }
        client = SupabaseClient(supabaseURL: url, supabaseKey: config.supabaseAnonKey)
        Task { await refreshSession() }
    }

    private func metaString(_ key: String) -> String? {
        session?.user.userMetadata[key]?.stringValue
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
            let newSession = try await client.auth.signInWithOAuth(
                provider: .google,
                redirectTo: URL(string: "ytlite://auth-callback")
            ) { (webSession: ASWebAuthenticationSession) in
                webSession.prefersEphemeralWebBrowserSession = false
            }
            session = newSession
        } catch {
            if isOAuthCancel(error) {
                lastError = nil
                return
            }
            lastError = error.localizedDescription
        }
    }

    /// Opens Google account picker. UI keeps the current account until the new login succeeds;
    /// cancel / failure restores the previous session.
    func switchGoogleAccount() async {
        guard let client else {
            lastError = "Supabase is not configured. Fill ios/Config/Secrets.xcconfig.local"
            return
        }
        isBusy = true
        lastError = nil
        defer { isBusy = false }

        let previous = session
        do {
            // Clear local auth so OAuth can establish a new session, but keep UI on `previous`.
            if previous != nil {
                try? await client.auth.signOut(scope: .local)
                session = previous
            }

            let newSession = try await client.auth.signInWithOAuth(
                provider: .google,
                redirectTo: URL(string: "ytlite://auth-callback"),
                queryParams: [(name: "prompt", value: "select_account")]
            ) { (webSession: ASWebAuthenticationSession) in
                webSession.prefersEphemeralWebBrowserSession = true
            }
            session = newSession
        } catch {
            await restoreSession(previous)
            if isOAuthCancel(error) {
                lastError = nil
            } else {
                lastError = error.localizedDescription
            }
        }
    }

    private func restoreSession(_ previous: Session?) async {
        guard let client, let previous else {
            session = previous
            return
        }
        do {
            session = try await client.auth.setSession(
                accessToken: previous.accessToken,
                refreshToken: previous.refreshToken
            )
        } catch {
            session = previous
        }
    }

    private func isOAuthCancel(_ error: Error) -> Bool {
        if let authError = error as? ASWebAuthenticationSessionError,
           authError.code == .canceledLogin {
            return true
        }
        return false
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
