import AuthenticationServices
import Foundation
import UIKit

/// Baidu Netdisk import via OAuth + file download APIs.
/// Requires `BAIDU_PAN_APP_KEY` / `BAIDU_PAN_SECRET_KEY` in Secrets / Info.plist.
@MainActor
final class BaiduPanImportClient: NSObject, ObservableObject {
    static let shared = BaiduPanImportClient()

    @Published private(set) var isAuthorized = false
    @Published var lastError: String?

    private let provider = "baidu"
    private var session: ASWebAuthenticationSession?

    struct PanFile: Identifiable, Hashable, Sendable {
        let id: String
        let path: String
        let name: String
        let isDir: Bool
        let size: Int64
    }

    private override init() {
        super.init()
        isAuthorized = ImportSourceStore.shared.token(provider: provider) != nil
    }

    private var baiduAppKey: String {
        Bundle.main.object(forInfoDictionaryKey: "BAIDU_PAN_APP_KEY") as? String ?? ""
    }

    private var baiduSecretKey: String {
        Bundle.main.object(forInfoDictionaryKey: "BAIDU_PAN_SECRET_KEY") as? String ?? ""
    }

    private var redirectURI: String { "ytlite://import-baidu" }

    func signIn() async {
        lastError = nil
        let appKey = baiduAppKey
        guard !appKey.isEmpty, !appKey.hasPrefix("$(") else {
            lastError = L("import.error.missing_baidu_keys")
            return
        }
        var comps = URLComponents(string: "https://openapi.baidu.com/oauth/2.0/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: appKey),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "basic,netdisk"),
            URLQueryItem(name: "display", value: "mobile")
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
            let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value
            guard let code else {
                lastError = L("import.error.oauth_failed")
                return
            }
            try await exchangeCode(code)
            isAuthorized = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signOut() {
        ImportSourceStore.shared.clearToken(provider: provider)
        isAuthorized = false
    }

    func list(path: String = "/") async throws -> [PanFile] {
        guard let access = ImportSourceStore.shared.token(provider: provider)?.access else {
            throw URLError(.userAuthenticationRequired)
        }
        var comps = URLComponents(string: "https://pan.baidu.com/rest/2.0/xpan/file")!
        comps.queryItems = [
            URLQueryItem(name: "method", value: "list"),
            URLQueryItem(name: "access_token", value: access),
            URLQueryItem(name: "dir", value: path),
            URLQueryItem(name: "limit", value: "100")
        ]
        let (data, response) = try await URLSession.shared.data(from: comps.url!)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(code) else { throw URLError(.badServerResponse) }
        struct ListResponse: Decodable {
            struct Item: Decodable {
                let fs_id: Int64
                let path: String
                let server_filename: String
                let isdir: Int
                let size: Int64
            }
            let list: [Item]?
            let errno: Int?
        }
        let decoded = try JSONDecoder().decode(ListResponse.self, from: data)
        if let errno = decoded.errno, errno != 0 {
            throw URLError(.cannotParseResponse)
        }
        return (decoded.list ?? []).map {
            PanFile(
                id: String($0.fs_id),
                path: $0.path,
                name: $0.server_filename,
                isDir: $0.isdir == 1,
                size: $0.size
            )
        }
    }

    /// Downloads file; for large files Baidu may return a redirect dlink — follow automatically via URLSession.
    func download(fsId: String) async throws -> Data {
        guard let access = ImportSourceStore.shared.token(provider: provider)?.access else {
            throw URLError(.userAuthenticationRequired)
        }
        // meta → dlink
        var metaComps = URLComponents(string: "https://pan.baidu.com/rest/2.0/xpan/multimedia")!
        metaComps.queryItems = [
            URLQueryItem(name: "method", value: "filemetas"),
            URLQueryItem(name: "access_token", value: access),
            URLQueryItem(name: "fsids", value: "[\(fsId)]"),
            URLQueryItem(name: "dlink", value: "1")
        ]
        let (metaData, metaResponse) = try await URLSession.shared.data(from: metaComps.url!)
        let metaCode = (metaResponse as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(metaCode) else { throw URLError(.badServerResponse) }
        struct Meta: Decodable {
            struct Item: Decodable { let dlink: String? }
            let list: [Item]?
        }
        let meta = try JSONDecoder().decode(Meta.self, from: metaData)
        guard var dlink = meta.list?.first?.dlink, !dlink.isEmpty else {
            throw URLError(.resourceUnavailable)
        }
        if !dlink.contains("access_token=") {
            dlink += (dlink.contains("?") ? "&" : "?") + "access_token=\(access)"
        }
        // Chunked read into memory (MVP). Large files should stream to disk in a follow-up.
        let (data, response) = try await URLSession.shared.data(from: URL(string: dlink)!)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(code) else { throw URLError(.badServerResponse) }
        return data
    }

    private func exchangeCode(_ code: String) async throws {
        var comps = URLComponents(string: "https://openapi.baidu.com/oauth/2.0/token")!
        comps.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: baiduAppKey),
            URLQueryItem(name: "client_secret", value: baiduSecretKey),
            URLQueryItem(name: "redirect_uri", value: redirectURI)
        ]
        let (data, response) = try await URLSession.shared.data(from: comps.url!)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(status) else { throw URLError(.badServerResponse) }
        struct Token: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double?
        }
        let token = try JSONDecoder().decode(Token.self, from: data)
        ImportSourceStore.shared.setToken(
            provider: provider,
            accessToken: token.access_token,
            refreshToken: token.refresh_token,
            expiry: Date().addingTimeInterval(token.expires_in ?? 2_592_000)
        )
    }
}

extension BaiduPanImportClient: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
