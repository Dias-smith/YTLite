import Foundation
import Security

/// Keychain-backed credentials for WebDAV / cloud import sources (no media).
@MainActor
final class ImportSourceStore: ObservableObject {
    static let shared = ImportSourceStore()

    struct WebDAVAccount: Codable, Identifiable, Equatable {
        var id: String
        var displayName: String
        var baseURL: String
        var username: String
        var rootPath: String
        /// Nutstore preset vs generic NAS.
        var preset: String?

        static func nutstore(username: String) -> WebDAVAccount {
            WebDAVAccount(
                id: UUID().uuidString,
                displayName: "Nutstore",
                baseURL: "https://dav.jianguoyun.com/dav/",
                username: username,
                rootPath: "/",
                preset: "nutstore"
            )
        }
    }

    @Published private(set) var webdavAccounts: [WebDAVAccount] = []

    private let accountsKey = "import.webdav.accounts"
    private init() {
        reload()
    }

    func reload() {
        guard let data = UserDefaults.standard.data(forKey: accountsKey),
              let decoded = try? JSONDecoder().decode([WebDAVAccount].self, from: data)
        else {
            webdavAccounts = []
            return
        }
        webdavAccounts = decoded
    }

    func saveAccounts(_ accounts: [WebDAVAccount]) {
        webdavAccounts = accounts
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: accountsKey)
        }
    }

    func upsert(_ account: WebDAVAccount, password: String) {
        var next = webdavAccounts.filter { $0.id != account.id }
        next.append(account)
        saveAccounts(next)
        setPassword(password, accountId: account.id)
    }

    func remove(accountId: String) {
        saveAccounts(webdavAccounts.filter { $0.id != accountId })
        deletePassword(accountId: accountId)
    }

    func password(for accountId: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.ytlite.player.import.webdav",
            kSecAttrAccount as String: accountId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func setPassword(_ password: String, accountId: String) {
        deletePassword(accountId: accountId)
        let data = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.ytlite.player.import.webdav",
            kSecAttrAccount as String: accountId,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func deletePassword(accountId: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.ytlite.player.import.webdav",
            kSecAttrAccount as String: accountId
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - OAuth tokens (Google Drive / Baidu)

    func setToken(provider: String, accessToken: String, refreshToken: String?, expiry: Date?) {
        let payload: [String: String] = [
            "access": accessToken,
            "refresh": refreshToken ?? "",
            "expiry": expiry.map { String($0.timeIntervalSince1970) } ?? ""
        ]
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let account = "oauth.\(provider)"
        deletePassword(accountId: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.ytlite.player.import.oauth",
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func token(provider: String) -> (access: String, refresh: String?, expiry: Date?)? {
        let account = "oauth.\(provider)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.ytlite.player.import.oauth",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let payload = try? JSONDecoder().decode([String: String].self, from: data),
              let access = payload["access"], !access.isEmpty
        else { return nil }
        let refresh = payload["refresh"].flatMap { $0.isEmpty ? nil : $0 }
        let expiry = payload["expiry"].flatMap(Double.init).map { Date(timeIntervalSince1970: $0) }
        return (access, refresh, expiry)
    }

    func clearToken(provider: String) {
        deleteOAuth(accountId: "oauth.\(provider)")
    }

    private func deleteOAuth(accountId: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.ytlite.player.import.oauth",
            kSecAttrAccount as String: accountId
        ]
        SecItemDelete(query as CFDictionary)
    }
}
