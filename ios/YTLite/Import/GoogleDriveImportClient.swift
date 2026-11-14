import AuthenticationServices
import Foundation
import UIKit

/// Google Drive read-only import. Uses client id from Info.plist `GOOGLE_CLIENT_ID` / Secrets.
@MainActor
final class GoogleDriveImportClient: NSObject, ObservableObject {
    static let shared = GoogleDriveImportClient()

    @Published private(set) var isAuthorized = false
    @Published var lastError: String?

    private let provider = "gdrive"
    private var session: ASWebAuthenticationSession?

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
        Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String ?? ""
    }

    private var redirectURI: String { "ytlite://import-gdrive" }

    func signIn() async {
        lastError = nil
        let clientID = googleClientID
        guard !clientID.isEmpty, !clientID.hasPrefix("$(") else {
            lastError = L("import.error.missing_google_client")
            return
        }
        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/drive.readonly"),
            URLQueryItem(name: "include_granted_scopes", value: "true"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        guard let authURL = comps.url else { return }
        do {
            let callback = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
                let session = ASWebAuthenticationSession(
                    url: authURL,
                    callbackURLScheme: "ytlite"
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
                session.prefersEphemeralWebBrowserSession = true
                self.session = session
                session.start()
            }
            guard let token = Self.fragmentValue(callback, key: "access_token") else {
                lastError = L("import.error.oauth_failed")
                return
            }
            let expiresIn = Self.fragmentValue(callback, key: "expires_in").flatMap(Double.init) ?? 3600
            ImportSourceStore.shared.setToken(
                provider: provider,
                accessToken: token,
                refreshToken: nil,
                expiry: Date().addingTimeInterval(expiresIn)
            )
            isAuthorized = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signOut() {
        ImportSourceStore.shared.clearToken(provider: provider)
        isAuthorized = false
    }

    func listAudioFiles(pageToken: String? = nil) async throws -> (files: [DriveFile], nextPage: String?) {
        guard let access = ImportSourceStore.shared.token(provider: provider)?.access else {
            throw URLError(.userAuthenticationRequired)
        }
        var comps = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        var q = "trashed=false and (mimeType contains 'audio/' or mimeType='video/mp4')"
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

    func download(fileId: String) async throws -> Data {
        guard let access = ImportSourceStore.shared.token(provider: provider)?.access else {
            throw URLError(.userAuthenticationRequired)
        }
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(code) else { throw URLError(.badServerResponse) }
        return data
    }

    private static func fragmentValue(_ url: URL, key: String) -> String? {
        let fragment = url.fragment ?? url.query ?? ""
        for pair in fragment.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2, parts[0] == key {
                return parts[1].removingPercentEncoding ?? parts[1]
            }
        }
        return nil
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
