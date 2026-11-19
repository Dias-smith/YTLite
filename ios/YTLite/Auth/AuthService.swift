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
    /// First launch session restore has finished (signed in or guest).
    @Published private(set) var hasResolvedSession = false
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
    /// Falls back to a per-user stored token when Supabase session refresh drops `providerToken`.
    var googleAccessToken: String? {
        guard authProvider != .apple else { return nil }
        if let live = session?.providerToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           !live.isEmpty
        {
            storeProviderToken(live)
            return live
        }
        return storedProviderToken()
    }

    private static let providerTokenKey = "auth.storedGoogleProviderToken"
    private static let providerTokenUserKey = "auth.storedGoogleProviderTokenUser"
    private static let providerRefreshKey = "auth.storedGoogleProviderRefreshToken"
    private static let googleDriveGrantedKey = "auth.googleDriveGranted"
    private static let googleDriveGrantedUserKey = "auth.googleDriveGrantedUser"

    /// `drive.readonly` — requested only via Drive import incremental / full OAuth.
    static let googleDriveReadonlyScope = "https://www.googleapis.com/auth/drive.readonly"

    /// Whether this Google user previously granted Drive read access in-app.
    var isGoogleDriveGranted: Bool {
        guard let userId,
              UserDefaults.standard.string(forKey: Self.googleDriveGrantedUserKey) == userId
        else { return false }
        return UserDefaults.standard.bool(forKey: Self.googleDriveGrantedKey)
    }

    func markGoogleDriveGranted() {
        guard let userId else { return }
        UserDefaults.standard.set(true, forKey: Self.googleDriveGrantedKey)
        UserDefaults.standard.set(userId, forKey: Self.googleDriveGrantedUserKey)
    }

    /// Clears Drive grant flag only (keeps Supabase / Subs session).
    func clearGoogleDriveGranted() {
        UserDefaults.standard.removeObject(forKey: Self.googleDriveGrantedKey)
        UserDefaults.standard.removeObject(forKey: Self.googleDriveGrantedUserKey)
    }

    private func storeProviderToken(_ token: String) {
        guard let userId else { return }
        UserDefaults.standard.set(token, forKey: Self.providerTokenKey)
        UserDefaults.standard.set(userId, forKey: Self.providerTokenUserKey)
    }

    private func storeRefreshToken(_ token: String) {
        guard let userId else { return }
        UserDefaults.standard.set(token, forKey: Self.providerRefreshKey)
        UserDefaults.standard.set(userId, forKey: Self.providerTokenUserKey)
    }

    private func storedProviderToken() -> String? {
        guard let userId,
              UserDefaults.standard.string(forKey: Self.providerTokenUserKey) == userId,
              let token = UserDefaults.standard.string(forKey: Self.providerTokenKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else { return nil }
        return token
    }

    private func storedRefreshToken() -> String? {
        guard let userId,
              UserDefaults.standard.string(forKey: Self.providerTokenUserKey) == userId,
              let token = UserDefaults.standard.string(forKey: Self.providerRefreshKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else { return nil }
        return token
    }

    private func clearStoredProviderToken() {
        UserDefaults.standard.removeObject(forKey: Self.providerTokenKey)
        UserDefaults.standard.removeObject(forKey: Self.providerTokenUserKey)
        UserDefaults.standard.removeObject(forKey: Self.providerRefreshKey)
    }

    /// Refreshes the Google provider access token when possible so You-page pulls see fresh likes.
    @discardableResult
    func ensureFreshGoogleAccessToken() async -> String? {
        guard authProvider != .apple else { return nil }

        if let rt = session?.providerRefreshToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rt.isEmpty
        {
            storeRefreshToken(rt)
        }
        if let live = session?.providerToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           !live.isEmpty
        {
            storeProviderToken(live)
        }

        let refresh = session?.providerRefreshToken ?? storedRefreshToken()
        if let refresh, !refresh.isEmpty,
           let fresh = await refreshGoogleAccessToken(using: refresh)
        {
            storeProviderToken(fresh)
            return fresh
        }
        return googleAccessToken
    }

    private func refreshGoogleAccessToken(using refreshToken: String) async -> String? {
        let clientId = AppConfig.fromBundle().googleClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientId.isEmpty else { return nil }
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id": clientId,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ]
        request.httpBody = body
            .map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value)"
            }
            .joined(separator: "&")
            .data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let access = json["access_token"] as? String,
                  !access.isEmpty
            else { return nil }
            if let newRefresh = json["refresh_token"] as? String, !newRefresh.isEmpty {
                storeRefreshToken(newRefresh)
            }
            return access
        } catch {
            return nil
        }
    }

    private static let googleOAuthScopes =
        SaltedLiteral.oauthReadonlyScope

    /// Subs scopes + Drive readonly for import (incremental or first-time Drive login).
    private static var googleOAuthScopesWithDrive: String {
        "\(googleOAuthScopes) \(googleDriveReadonlyScope)"
    }

    init(config: AppConfig) {
        guard config.isConfigured,
              let url = URL(string: config.supabaseURL)
        else {
            hasResolvedSession = true
            return
        }
        client = SupabaseClient(supabaseURL: url, supabaseKey: config.supabaseAnonKey)
        Task { await refreshSession() }
    }

    private func metaString(_ key: String) -> String? {
        session?.user.userMetadata[key]?.stringValue
    }

    func refreshSession() async {
        guard let client else {
            hasResolvedSession = true
            return
        }
        do {
            session = try await client.auth.session
        } catch {
            session = nil
        }
        hasResolvedSession = true
    }

    func signInWithGoogle(source: String = "unknown") async {
        AppAnalytics.signInStart(provider: "google", source: source)
        let ok = await performGoogleOAuth(
            scopes: Self.googleOAuthScopes,
            queryParams: [
                // Ensure catalog.readonly is (re)granted — incremental auth / stale sessions often omit it.
                (name: "prompt", value: "consent"),
                (name: "access_type", value: "offline"),
            ],
            ephemeral: false
        )
        if ok {
            AppAnalytics.signInSuccess(provider: "google")
        } else if lastError != nil {
            AppAnalytics.signInFail(provider: "google", error: lastError ?? "unknown")
        }
    }

    /// Ensures Google OAuth includes `drive.readonly`. Reuses Subs Google session via incremental consent.
    /// After success the user has a Supabase Google session (Subs already signed in).
    @discardableResult
    func ensureGoogleDriveAccess(source: String = "import") async -> Bool {
        AppAnalytics.signInStart(provider: "google", source: source)
        if authProvider == .google, isGoogleDriveGranted, googleAccessToken != nil {
            if let fresh = await ensureFreshGoogleAccessToken(), !fresh.isEmpty {
                AppAnalytics.signInSuccess(provider: "google")
                return true
            }
        }

        let alreadyGoogle = authProvider == .google
        let ok = await performGoogleOAuth(
            scopes: Self.googleOAuthScopesWithDrive,
            queryParams: [
                (name: "include_granted_scopes", value: "true"),
                (name: "access_type", value: "offline"),
                // Incremental: consent for new Drive scope; avoid select_account so Subs account is reused.
                (name: "prompt", value: "consent"),
            ],
            ephemeral: false
        )
        if ok {
            markGoogleDriveGranted()
            AppAnalytics.signInSuccess(provider: "google")
            #if DEBUG
            print("[YTLite.Auth] Drive access granted (incremental=\(alreadyGoogle))")
            #endif
            return true
        }
        if lastError != nil {
            AppAnalytics.signInFail(provider: "google", error: lastError ?? "unknown")
        }
        return false
    }

    /// Shared Supabase Google OAuth. Does not default-include Drive (Subs stays minimal-scope).
    @discardableResult
    private func performGoogleOAuth(
        scopes: String,
        queryParams: [(name: String, value: String)],
        ephemeral: Bool
    ) async -> Bool {
        guard let client else {
            lastError = "Supabase is not configured. Fill ios/Config/Secrets.xcconfig.local"
            return false
        }
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            let newSession = try await client.auth.signInWithOAuth(
                provider: .google,
                redirectTo: URL(string: "ytlite://auth-callback"),
                scopes: scopes,
                queryParams: queryParams
            ) { (webSession: ASWebAuthenticationSession) in
                webSession.prefersEphemeralWebBrowserSession = ephemeral
            }
            session = newSession
            if let token = newSession.providerToken, !token.isEmpty {
                storeProviderToken(token)
            }
            if let refresh = newSession.providerRefreshToken, !refresh.isEmpty {
                storeRefreshToken(refresh)
            }
            return true
        } catch {
            if isOAuthCancel(error) {
                lastError = nil
                return false
            }
            lastError = error.localizedDescription
            return false
        }
    }

    func signInWithApple(source: String = "unknown") async {
        AppAnalytics.signInStart(provider: "apple", source: source)
        guard client != nil else {
            lastError = "Supabase is not configured. Fill ios/Config/Secrets.xcconfig.local"
            AppAnalytics.signInFail(provider: "apple", error: lastError ?? "not_configured")
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
            AppAnalytics.signInSuccess(provider: "apple")
        } catch {
            if isAppleCancel(error) {
                lastError = nil
                return
            }
            lastError = error.localizedDescription
            AppAnalytics.signInFail(provider: "apple", error: lastError ?? "unknown")
        }
    }

    /// Completes Sign in with Apple from `SignInWithAppleButton`.
    func completeAppleSignIn(
        result: Result<ASAuthorization, Error>,
        rawNonce: String?,
        source: String = "unknown"
    ) async {
        AppAnalytics.signInStart(provider: "apple", source: source)
        guard client != nil else {
            lastError = "Supabase is not configured. Fill ios/Config/Secrets.xcconfig.local"
            AppAnalytics.signInFail(provider: "apple", error: lastError ?? "not_configured")
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
                AppAnalytics.signInFail(provider: "apple", error: lastError ?? "unknown")
            }
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let rawNonce, !rawNonce.isEmpty
            else {
                lastError = AppleSignInError.invalidCredential.localizedDescription
                AppAnalytics.signInFail(provider: "apple", error: lastError ?? "invalid_credential")
                return
            }
            do {
                try await applyAppleIdToken(
                    idToken: idToken,
                    rawNonce: rawNonce,
                    fullName: credential.fullName
                )
                AppAnalytics.signInSuccess(provider: "apple")
            } catch {
                lastError = error.localizedDescription
                AppAnalytics.signInFail(provider: "apple", error: lastError ?? "unknown")
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
                queryParams: [
                    (name: "prompt", value: "select_account consent"),
                    (name: "access_type", value: "offline"),
                ]
            ) { (webSession: ASWebAuthenticationSession) in
                webSession.prefersEphemeralWebBrowserSession = true
            }
            session = newSession
            if let token = newSession.providerToken, !token.isEmpty {
                storeProviderToken(token)
            }
            if let refresh = newSession.providerRefreshToken, !refresh.isEmpty {
                storeRefreshToken(refresh)
            }
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
        let text = error.localizedDescription.lowercased()
        if text.contains("cancel") { return true }
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
            clearStoredProviderToken()
            clearGoogleDriveGranted()
            AppAnalytics.signOut()
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
            clearStoredProviderToken()
            clearGoogleDriveGranted()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func supabaseClient() -> SupabaseClient? { client }
}
