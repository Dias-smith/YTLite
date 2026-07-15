import Foundation

enum YouTubeConstants {
    static let apiKey = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
    static let baseURL = "https://www.youtube.com"
    static let searchURL = "\(baseURL)/youtubei/v1/search?key=\(apiKey)"
    static let userAgent =
        "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
    static let hl = "en"
    static let gl = "US"
    static let webClientName = "WEB"
    static let webClientVersion = "2.20260701.01.00"
    static let webClientNameHeader = "1"
    static let preferredVideoItags = [37, 22, 18]
    static let preferredAudioItags = [140, 141, 139]
}

struct HttpStringResult: Sendable {
    var success: Bool
    var body: String
    var errCode: Int
    var errMsg: String
}

actor YouTubeHTTPClient {
    static let shared = YouTubeHTTPClient()

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 45
        config.httpAdditionalHeaders = [
            "Accept-Encoding": "gzip, deflate",
        ]
        return URLSession(configuration: config)
    }()

    func request(
        url: String,
        method: String,
        headers: [String: String],
        body: String?
    ) async -> HttpStringResult {
        guard let requestURL = URL(string: url) else {
            return HttpStringResult(success: false, body: "", errCode: -1, errMsg: "Invalid URL")
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = method.uppercased()
        let enriched = enrichYouTubeHeaders(url: url, method: method, headers: headers)
        for (key, value) in enriched where !key.isEmpty && !value.isEmpty {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let body, method.uppercased() == "POST" {
            request.httpBody = Data(body.utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            var text = String(data: data, encoding: .utf8) ?? ""
            text = Self.stripYouTubeJSONPrefix(text)
            if (200..<300).contains(status) {
                return HttpStringResult(success: true, body: text, errCode: status, errMsg: "")
            }
            return HttpStringResult(
                success: false,
                body: text,
                errCode: status,
                errMsg: "HTTP \(status)"
            )
        } catch {
            return HttpStringResult(
                success: false,
                body: "",
                errCode: -1,
                errMsg: error.localizedDescription
            )
        }
    }

    private func enrichYouTubeHeaders(
        url: String,
        method: String,
        headers: [String: String]
    ) -> [String: String] {
        guard url.contains("youtube.com") else { return headers }
        var enriched = headers
        if enriched.keys.first(where: { $0.caseInsensitiveCompare("Accept") == .orderedSame }) == nil {
            enriched["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        }
        if enriched.keys.first(where: { $0.caseInsensitiveCompare("Accept-Language") == .orderedSame }) == nil {
            enriched["Accept-Language"] = "en-US,en;q=0.9"
        }
        let uaKey = enriched.keys.first { $0.caseInsensitiveCompare("User-Agent") == .orderedSame }
        let ua = uaKey.flatMap { enriched[$0] }
        if ua == nil || ua?.contains("Chrome/75") == true {
            if let uaKey { enriched.removeValue(forKey: uaKey) }
            enriched["User-Agent"] = YouTubeConstants.userAgent
        }
        if method.uppercased() == "GET" {
            enriched["Sec-Fetch-Mode"] = enriched["Sec-Fetch-Mode"] ?? "navigate"
            enriched["Sec-Fetch-Dest"] = enriched["Sec-Fetch-Dest"] ?? "document"
        }
        return enriched
    }

    static func stripYouTubeJSONPrefix(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(")]}'") {
            if let idx = trimmed.firstIndex(of: "\n") {
                return String(trimmed[trimmed.index(after: idx)...])
            }
            return String(trimmed.dropFirst(4))
        }
        return trimmed
    }
}
