import Foundation

/// Google Drive read-only import via AuthService Supabase Google OAuth (`drive.readonly`).
@MainActor
final class GoogleDriveImportClient: ObservableObject {
    static let shared = GoogleDriveImportClient()

    @Published private(set) var isAuthorized = false
    @Published var lastError: String?

    private let provider = "gdrive"
    private weak var auth: AuthService?

    struct DriveFile: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let mimeType: String
        let size: Int64?
    }

    private init() {
        isAuthorized = ImportSourceStore.shared.token(provider: provider) != nil
    }

    /// Bind the shared AuthService (call from the import sheet).
    func attach(auth: AuthService) {
        self.auth = auth
        syncAuthorizedFlag(auth: auth)
    }

    func syncAuthorizedFlag(auth: AuthService) {
        if auth.authProvider == .google, auth.isGoogleDriveGranted, auth.googleAccessToken != nil {
            isAuthorized = true
            return
        }
        isAuthorized = ImportSourceStore.shared.token(provider: provider) != nil
    }

    /// Incremental Drive consent when Subs Google is already signed in; otherwise full Google+Drive OAuth.
    func signIn(auth: AuthService) async {
        lastError = nil
        self.auth = auth
        let ok = await auth.ensureGoogleDriveAccess(source: "import_gdrive")
        guard ok else {
            lastError = auth.lastError ?? L("import.error.oauth_failed")
            isAuthorized = false
            return
        }
        if let token = await auth.ensureFreshGoogleAccessToken() ?? auth.googleAccessToken {
            cacheToken(token)
        }
        isAuthorized = true
    }

    /// Clears Drive grant + cached token. Does **not** sign out Subs / Supabase.
    func signOut(auth: AuthService? = nil) {
        let auth = auth ?? self.auth
        ImportSourceStore.shared.clearToken(provider: provider)
        auth?.clearGoogleDriveGranted()
        isAuthorized = false
        lastError = nil
    }

    func listAudioFiles(pageToken: String? = nil) async throws -> (files: [DriveFile], nextPage: String?) {
        let access = try await resolvedAccessToken()
        var comps = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        let q = "trashed=false and (mimeType contains 'audio/' or mimeType='video/mp4')"
        comps.queryItems = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "fields", value: "nextPageToken,files(id,name,mimeType,size)"),
            URLQueryItem(name: "pageSize", value: "50")
        ]
        if let pageToken {
            comps.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
        }
        var request = URLRequest(url: comps.url!)
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        if code == 401 || code == 403 {
            revokeLocalDriveAuth()
            throw URLError(.userAuthenticationRequired)
        }
        guard (200...299).contains(code) else { throw URLError(.badServerResponse) }
        struct Page: Decodable {
            struct File: Decodable {
                let id: String
                let name: String
                let mimeType: String
                let size: String?
            }
            let files: [File]?
            let nextPageToken: String?
        }
        let page = try JSONDecoder().decode(Page.self, from: data)
        let files = (page.files ?? []).map {
            DriveFile(id: $0.id, name: $0.name, mimeType: $0.mimeType, size: $0.size.flatMap(Int64.init))
        }
        return (files, page.nextPageToken)
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

    private func resolvedAccessToken() async throws -> String {
        if let auth {
            if let token = await auth.ensureFreshGoogleAccessToken() ?? auth.googleAccessToken,
               !token.isEmpty
            {
                cacheToken(token)
                return token
            }
        }
        if let cached = ImportSourceStore.shared.token(provider: provider)?.access, !cached.isEmpty {
            return cached
        }
        isAuthorized = false
        throw URLError(.userAuthenticationRequired)
    }

    private func cacheToken(_ access: String) {
        ImportSourceStore.shared.setToken(
            provider: provider,
            accessToken: access,
            refreshToken: nil,
            expiry: Date().addingTimeInterval(3500)
        )
    }

    private func revokeLocalDriveAuth() {
        ImportSourceStore.shared.clearToken(provider: provider)
        auth?.clearGoogleDriveGranted()
        isAuthorized = false
        lastError = L("import.error.oauth_failed")
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
