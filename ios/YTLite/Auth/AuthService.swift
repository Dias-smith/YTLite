import Foundation
import Supabase
import AuthenticationServices

enum AuthProviderKind: String {
    case google
    case apple
}

@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var session: Session?
    @Published private(set) var isBusy = false
    @Published var lastError: String?

    private var client: SupabaseClient?
    private let appleBridge = AppleSignInBridge()

    var isAuthenticated: Bool { session != nil }
    var userId: String? { session?.user.id.uuidString.lowercased() }
    var isConfigured: Bool { client != nil }

    /// Active social provider for the current Supabase session.
    var authProvider: AuthProviderKind? {
        guard let session else { return nil }
        if let provider = session.user.appMetadata["provider"]?.stringValue?.lowercased() {
            if provider == "apple" { return .apple }
            if provider == "google" { return .google }
        }
        let identities = session.user.identities ?? []
        if identities.contains(where: { $0.provider == "apple" }) { return .apple }
        if identities.contains(where: { $0.provider == "google" }) { return .google }
        return nil
    }

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

    /// Google OAuth access token. Nil for Apple-only sessions.
    var googleAccessToken: String? {
        guard authProvider != .apple else { return nil }
        return session?.providerToken
    }

    private static let googleOAuthScopes =
        "openid email profile https://www.googleapis.com/auth/youtube.readonly"

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
                redirectTo: URL(string: "ytlite://auth-callback"),
                scopes: Self.googleOAuthScopes
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

    func signInWithApple() async {
        guard client != nil else {
            lastError = "Supabase is not configured. Fill ios/Config/Secrets.xcconfig.local"
            return
        }
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            let apple = try await appleBridge.signIn()
            try await applyAppleIdToken(
                idToken: apple.idToken,
                rawNonce: apple.rawNonce,
                fullName: apple.fullName
            )
        } catch {
            if isAppleCancel(error) {
                lastError = nil
                return
            }
            lastError = error.localizedDescription
        }
    }

    /// Completes Sign in with Apple from `SignInWithAppleButton`.
    func completeAppleSignIn(
        result: Result<ASAuthorization, Error>,
        rawNonce: String?
    ) async {
        guard client != nil else {
            lastError = "Supabase is not configured. Fill ios/Config/Secrets.xcconfig.local"
            return
        }
        isBusy = true
        lastError = nil
        defer { isBusy = false }

        switch result {
        case .failure(let error):
            if isAppleCancel(error) {
                lastError = nil
            } else {
                lastError = error.localizedDescription
            }
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let rawNonce, !rawNonce.isEmpty
            else {
                lastError = AppleSignInError.invalidCredential.localizedDescription
                return
            }
            do {
                try await applyAppleIdToken(
                    idToken: idToken,
                    rawNonce: rawNonce,
                    fullName: credential.fullName
                )
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private func applyAppleIdToken(
        idToken: String,
        rawNonce: String,
        fullName: PersonNameComponents?
    ) async throws {
        guard let client else { return }
        let newSession = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: idToken,
                nonce: rawNonce
            )
        )
        session = newSession
        if let name = formattedName(fullName), !name.isEmpty {
            _ = try? await client.auth.update(
                user: UserAttributes(data: ["full_name": .string(name)])
            )
            await refreshSession()
        }
    }

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
            if previous != nil {
                try? await client.auth.signOut(scope: .local)
                session = previous
            }

            let newSession = try await client.auth.signInWithOAuth(
                provider: .google,
                redirectTo: URL(string: "ytlite://auth-callback"),
                scopes: Self.googleOAuthScopes,
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

    func switchAppleAccount() async {
        guard let client else {
            lastError = "Supabase is not configured. Fill ios/Config/Secrets.xcconfig.local"
            return
        }
        isBusy = true
        lastError = nil
        defer { isBusy = false }

        let previous = session
        do {
            if previous != nil {
                try? await client.auth.signOut(scope: .local)
                session = previous
            }
            let apple = try await appleBridge.signIn()
            try await applyAppleIdToken(
                idToken: apple.idToken,
                rawNonce: apple.rawNonce,
                fullName: apple.fullName
            )
        } catch {
            await restoreSession(previous)
            if isAppleCancel(error) {
                lastError = nil
            } else {
                lastError = error.localizedDescription
            }
        }
    }

    func switchAccount() async {
        switch authProvider {
        case .apple:
            await switchAppleAccount()
        case .google, .none:
            await switchGoogleAccount()
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

    private func isAppleCancel(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == ASAuthorizationError.errorDomain,
           ns.code == ASAuthorizationError.canceled.rawValue {
            return true
        }
        return false
    }

    private func formattedName(_ components: PersonNameComponents?) -> String? {
        guard let components else { return nil }
        let formatter = PersonNameComponentsFormatter()
        let value = formatter.string(from: components).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
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

    @discardableResult
    func deleteAccount() async -> Bool {
        guard let client else {
            lastError = "Supabase is not configured"
            return false
        }
        guard let accessToken = session?.accessToken else {
            lastError = "Not signed in"
            return false
        }

        isBusy = true
        lastError = nil
        defer { isBusy = false }

        do {
            try await client.functions.invoke(
                "delete-account",
                options: FunctionInvokeOptions(
                    method: .post,
                    headers: ["Authorization": "Bearer \(accessToken)"]
                )
            )
            try? await client.auth.signOut(scope: .local)
            session = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func supabaseClient() -> SupabaseClient? { client }
}
