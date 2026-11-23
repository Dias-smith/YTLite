import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Google Drive import via `drive.file` + official OAuth file picker (`trigger_onepick`).
/// Separate from Supabase / YouTube Google login — onepick permits only `drive.file`.
@MainActor
final class GoogleDriveImportClient: NSObject, ObservableObject {
    static let shared = GoogleDriveImportClient()

    static let driveFileScope = "https://www.googleapis.com/auth/drive.file"

    @Published private(set) var isAuthorized = false
    @Published var lastError: String?

    private let provider = "gdrive"
    private var session: ASWebAuthenticationSession?
    /// Web OAuth clients reject custom schemes (`ytlite://…`) → Error 400 invalid_request.
    /// HTTPS page on ytlite.cc bridges into `ytlite://gdrive-picker` for ASWebAuthenticationSession.
    private var redirectURI: String { "https://www.ytlite.cc/oauth/gdrive-picker.html" }
    private var callbackScheme: String { "ytlite" }

    struct DriveFile: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let mimeType: String
        let size: Int64?
    }

    private override init() {
        super.init()
        isAuthorized = ImportSourceStore.shared.token(provider: provider) != nil
    }

    private var googleClientID: String {
        AppConfig.fromBundle().googleClientID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Web application clients need this for `authorization_code` exchange (iOS clients use PKCE only).
    private var googleClientSecret: String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_SECRET") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty || raw.hasPrefix("$(") { return "" }
        return raw
    }

    private static func formBody(_ fields: [String: String]) -> Data? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":/?&=+$#")
        return fields
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
            .data(using: .utf8)
    }

    private static func googleOAuthErrorMessage(data: Data, status: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let err = (json["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let desc = (json["error_description"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let err, let desc, !desc.isEmpty { return "\(err): \(desc)" }
            if let err, !err.isEmpty { return err }
            if let desc, !desc.isEmpty { return desc }
        }
        return "HTTP \(status)"
    }

    /// Opens Google OAuth with `trigger_onepick`, exchanges the code, then loads metadata for picked IDs.
    func pickFiles() async -> [DriveFile] {
        lastError = nil
        let clientId = googleClientID
        guard !clientId.isEmpty, !clientId.hasPrefix("$(") else {
            lastError = L("import.error.oauth_failed")
            return []
        }

        let verifier = Self.makeCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)

        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.driveFileScope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "trigger_onepick", value: "true"),
            URLQueryItem(name: "allow_multiple", value: "true"),
            URLQueryItem(
                name: "mimetypes",
                value: "audio/mpeg,audio/mp4,audio/x-m4a,audio/wav,audio/x-wav,audio/flac,audio/aiff,audio/x-aiff,video/mp4,video/quicktime"
            ),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let authURL = comps.url else {
            lastError = L("import.error.oauth_failed")
            return []
        }

        do {
            let callback = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
                let session = ASWebAuthenticationSession(
                    url: authURL,
                    callbackURLScheme: callbackScheme
                ) { url, error in
                    if let error {
                        cont.resume(throwing: error)
                    } else if let url {
                        cont.resume(returning: url)
                    } else {
                        cont.resume(throwing: URLError(.badServerResponse))
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                self.session = session
                session.start()
            }

            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if items.contains(where: { $0.name == "error" }) {
                lastError = nil
                return []
            }
            guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
                lastError = L("import.error.oauth_failed")
                return []
            }
            let pickedRaw = items.first(where: { $0.name == "picked_file_ids" })?.value ?? ""
            let fileIds = pickedRaw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            try await exchangeCode(code, verifier: verifier)
            isAuthorized = true

            guard !fileIds.isEmpty else { return [] }
            var files: [DriveFile] = []
            for id in fileIds {
                if let meta = try await fetchMetadata(fileId: id) {
                    files.append(meta)
                }
            }
            return files
        } catch {
            if Self.isCancel(error) {
                lastError = nil
            } else {
                lastError = error.localizedDescription
            }
            return []
        }
    }

    func signOut() {
        ImportSourceStore.shared.clearToken(provider: provider)
        isAuthorized = false
        lastError = nil
    }

    func download(
        fileId: String,
        expectedBytes: Int64? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Data {
        let access = try await resolvedAccessToken()
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        let loader = DriveFileBodyDownload(expectedBytes: expectedBytes, onProgress: onProgress)
        do {
            return try await loader.fetch(request)
        } catch let error as URLError where error.code == .userAuthenticationRequired {
            revokeLocalDriveAuth()
            throw error
        }
    }

    // MARK: - Private

    private func fetchMetadata(fileId: String) async throws -> DriveFile? {
        let access = try await resolvedAccessToken()
        var comps = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(fileId)")!
        comps.queryItems = [
            URLQueryItem(name: "fields", value: "id,name,mimeType,size")
        ]
        var request = URLRequest(url: comps.url!)
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        if code == 401 || code == 403 {
            revokeLocalDriveAuth()
            throw URLError(.userAuthenticationRequired)
        }
        guard (200...299).contains(code) else { throw URLError(.badServerResponse) }
        struct Meta: Decodable {
            let id: String
            let name: String
            let mimeType: String
            let size: String?
        }
        let meta = try JSONDecoder().decode(Meta.self, from: data)
        return DriveFile(
            id: meta.id,
            name: meta.name,
            mimeType: meta.mimeType,
            size: meta.size.flatMap(Int64.init)
        )
    }

    private func resolvedAccessToken() async throws -> String {
        if let cached = ImportSourceStore.shared.token(provider: provider) {
            if let expiry = cached.expiry, expiry > Date().addingTimeInterval(60),
               !cached.access.isEmpty
            {
                return cached.access
            }
            if let refresh = cached.refresh, !refresh.isEmpty,
               let fresh = await refreshAccessToken(using: refresh)
            {
                return fresh
            }
            if !cached.access.isEmpty {
                return cached.access
            }
        }
        isAuthorized = false
        throw URLError(.userAuthenticationRequired)
    }

    private func exchangeCode(_ code: String, verifier: String) async throws {
        let clientId = googleClientID
        let secret = googleClientSecret
        guard !secret.isEmpty else {
            throw NSError(
                domain: "YTLite.GoogleDrive",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Missing GOOGLE_CLIENT_SECRET. Open Google Cloud → Credentials → Mixtube Web Backend → copy Client secret into ios/Config/Secrets.xcconfig.local",
                ]
            )
        }
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var fields: [String: String] = [
            "client_id": clientId,
            "client_secret": secret,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ]
        request.httpBody = Self.formBody(fields)

        // Avoid URLSession turning HTTP 401 + WWW-Authenticate into NSURLError -1013.
        let (data, response) = try await OAuthHTTP.post(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(status) else {
            throw NSError(
                domain: "YTLite.GoogleDrive",
                code: status,
                userInfo: [NSLocalizedDescriptionKey: Self.googleOAuthErrorMessage(data: data, status: status)]
            )
        }
        struct Token: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double?
        }
        let token = try JSONDecoder().decode(Token.self, from: data)
        let existingRefresh = ImportSourceStore.shared.token(provider: provider)?.refresh
        ImportSourceStore.shared.setToken(
            provider: provider,
            accessToken: token.access_token,
            refreshToken: token.refresh_token ?? existingRefresh,
            expiry: Date().addingTimeInterval(token.expires_in ?? 3500)
        )
    }

    private func refreshAccessToken(using refreshToken: String) async -> String? {
        let clientId = googleClientID
        let secret = googleClientSecret
        guard !clientId.isEmpty, let url = URL(string: "https://oauth2.googleapis.com/token") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var fields: [String: String] = [
            "client_id": clientId,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ]
        if !secret.isEmpty {
            fields["client_secret"] = secret
        }
        request.httpBody = Self.formBody(fields)
        do {
            let (data, response) = try await OAuthHTTP.post(request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let access = json["access_token"] as? String,
                  !access.isEmpty
            else { return nil }
            let expires = (json["expires_in"] as? Double) ?? 3500
            let newRefresh = (json["refresh_token"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ImportSourceStore.shared.setToken(
                provider: provider,
                accessToken: access,
                refreshToken: newRefresh ?? refreshToken,
                expiry: Date().addingTimeInterval(expires)
            )
            isAuthorized = true
            return access
        } catch {
            return nil
        }
    }

    private func revokeLocalDriveAuth() {
        ImportSourceStore.shared.clearToken(provider: provider)
        isAuthorized = false
        lastError = L("import.error.oauth_failed")
    }

    private static func isCancel(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == ASWebAuthenticationSessionError.errorDomain,
           ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
        {
            return true
        }
        if ns.domain == NSURLErrorDomain {
            // -999 cancelled, -1013 userCancelledAuthentication (sheet closed / auth challenge).
            if ns.code == NSURLErrorCancelled || ns.code == NSURLErrorUserCancelledAuthentication {
                return true
            }
        }
        return false
    }

    private static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension GoogleDriveImportClient: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

/// Token endpoint helper: reject HTTP auth challenges so 401 bodies are returned (not -1013).
private final class OAuthHTTP: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static func post(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let delegate = OAuthHTTP()
        let session = URLSession(
            configuration: .ephemeral,
            delegate: delegate,
            delegateQueue: nil
        )
        defer { session.finishTasksAndInvalidate() }
        return try await session.data(for: request)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.rejectProtectionSpace, nil)
        }
    }
}

/// Streams a Drive media body so the caller can show per-file progress.
private final class DriveFileBodyDownload: NSObject, URLSessionDataDelegate {
    private let onProgress: (@Sendable (Double) -> Void)?
    private var session: URLSession?
    private var continuation: CheckedContinuation<Data, Error>?
    private var buffer = Data()
    private var expected: Int64
    private var received: Int64 = 0
    private var statusCode = -1
    private var lastFraction = -1.0

    init(expectedBytes: Int64?, onProgress: (@Sendable (Double) -> Void)?) {
        let hint = expectedBytes ?? -1
        self.expected = hint > 0 ? hint : -1
        self.onProgress = onProgress
    }

    func fetch(_ request: URLRequest) async throws -> Data {
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        self.session = session
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.dataTask(with: request).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        if response.expectedContentLength > 0 {
            expected = response.expectedContentLength
        }
        if (200...299).contains(statusCode) {
            completionHandler(.allow)
        } else {
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        received += Int64(data.count)
        guard expected > 0, let onProgress else { return }
        let fraction = min(0.99, Double(received) / Double(expected))
        guard fraction - lastFraction >= 0.02 else { return }
        lastFraction = fraction
        onProgress(fraction)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let result: Result<Data, Error>
        if statusCode == 401 || statusCode == 403 {
            result = .failure(URLError(.userAuthenticationRequired))
        } else if !(200...299).contains(statusCode) {
            result = .failure(error ?? URLError(.badServerResponse))
        } else if let error {
            result = .failure(error)
        } else {
            result = .success(buffer)
        }
        let continuation = self.continuation
        self.continuation = nil
        self.session?.finishTasksAndInvalidate()
        self.session = nil
        continuation?.resume(with: result)
    }
}
