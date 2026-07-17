import Foundation
import UIKit

/// Public web / store / mail destinations used by Settings and legal links.
enum AppLinks {
    /// Prefer `www` — apex `ytlite.cc` currently serves a `*.github.io` cert (Safari hostname mismatch).
    static let privacyPolicy = URL(string: "https://www.ytlite.cc/privacy.html")!
    static let termsOfService = URL(string: "https://www.ytlite.cc/terms.html")!
    static let support = URL(string: "https://www.ytlite.cc/support.html")!
    static let suggestionsEmail = "jimo.cgg@gmail.com"

    /// Numeric App Store ID (no “id” prefix). From `APP_STORE_ID` in Secrets.xcconfig.
    static var appStoreId: String? {
        let raw = Bundle.main.object(forInfoDictionaryKey: "APP_STORE_ID") as? String
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Opens the App Store “Write a Review” page when `APP_STORE_ID` is configured.
    static var writeReviewURL: URL? {
        guard let id = appStoreId else { return nil }
        return URL(string: "itms-apps://itunes.apple.com/app/id\(id)?action=write-review")
    }

    /// Public App Store product page.
    static var appStoreURL: URL? {
        guard let id = appStoreId else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(id)")
    }

    static func suggestionsMailtoURL(subject: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = suggestionsEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
        ]
        return components.url
    }

    @MainActor
    static func open(_ url: URL) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}
