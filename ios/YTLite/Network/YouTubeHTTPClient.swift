import Foundation

/// Normalize watch / Shorts / youtu.be URLs before extract.
enum YouTubeURL {
    /// `https://www.youtube.com/watch?v={id}`
    static func watchURL(videoId: String) -> String {
        "\(YouTubeConstants.baseURL)/watch?v=\(videoId)"
    }

    /// Convert Shorts (and similar) URLs to a canonical watch URL before parsing.
    /// e.g. `https://www.youtube.com/shorts/26beJql1QWY` → `https://www.youtube.com/watch?v=26beJql1QWY`
    static func canonicalWatchURL(_ urlString: String) -> String {
        if let id = videoId(from: urlString) {
            return watchURL(videoId: id)
        }
        return urlString
    }

    static func videoId(from urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Bare 11-char video id.
        if trimmed.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil {
            return trimmed
        }

        guard let url = URL(string: trimmed) else { return nil }
        if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "v" })?
            .value,
           !v.isEmpty
        {
            return v
        }

        let parts = url.path.split(separator: "/").map(String.init)
        if let idx = parts.firstIndex(where: { $0 == "shorts" || $0 == "embed" || $0 == "v" || $0 == "live" }),
           parts.index(after: idx) < parts.endIndex
        {
            let id = parts[parts.index(after: idx)]
            if id.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil {
                return id
            }
        }

        // youtu.be/{id}
        if let host = url.host?.lowercased(),
           (host == "youtu.be" || host.hasSuffix(".youtu.be")),
           let id = parts.first,
           id.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil
        {
            return id
        }
        return nil
    }
}

enum YouTubeConstants {
    static let apiKey = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
    static let musicApiKey = "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30"
    /// Data API key for Search hot keywords (`videos.list` mostPopular Music) — Android `YoutubeDataApiConfig.HOT_KEYWORDS_API_KEY`.
    static let hotKeywordsApiKey = "AIzaSyAbMOfstY2zu-C9zxHBbtXRh9ybYcbpeYc"
    static let hotKeywordsLimit = 10
    static let baseURL = "https://www.youtube.com"
    static let musicBaseURL = "https://music.youtube.com"
    static let searchURL = "\(baseURL)/youtubei/v1/search?key=\(apiKey)"
    static let musicSearchURL = "\(musicBaseURL)/youtubei/v1/search?key=\(musicApiKey)"
    static let musicBrowseURL = "\(musicBaseURL)/youtubei/v1/browse?key=\(musicApiKey)"
    /// YouTube Music `/next` (RDAMVM radio / Related tab).
    static let musicNextURL = "\(musicBaseURL)/youtubei/v1/next?key=\(musicApiKey)"
    /// YouTube Music new-release albums shelf.
    static let musicBrowseIdNewReleaseAlbums = "FEmusic_new_releases_albums"
    static let userAgent =
        "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
    /// HTTP headers googlevideo expects (match Android ExoPlayer `PlaybackService`).
    static var streamPlaybackHeaders: [String: String] {
        [
            "User-Agent": userAgent,
            "Referer": "https://www.youtube.com/",
            "Origin": "https://www.youtube.com",
        ]
    }
    static let hl = "en"
    static let gl = "US"
    static let webClientName = "WEB"
    static let webClientVersion = "2.20260701.01.00"
    static let webClientNameHeader = "1"
    /// YouTube Music web client (`music.youtube.com`).
    static let musicClientName = "WEB_REMIX"
    static let musicClientVersion = "1.20250317.01.00"
    static let musicClientNameHeader = "67"
    /// InnerTube songs filter for YouTube Music search.
    static let musicSearchParamsSongs = "EgWKAQIIAWoKEAMQBBAJEAoQBQ%3D%3D"
    /// Playback preference: progressive 360p muxed first (AVPlayer-friendly), then higher muxed.
    /// Overridden at runtime by remote extractor manifest `config.preferItags` when available.
    private static let lock = NSLock()
    private static var _preferredVideoItags = [18, 22, 37]
    static var preferredVideoItags: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return _preferredVideoItags
    }

    static func applyPreferredVideoItags(_ itags: [Int]) {
        guard !itags.isEmpty else { return }
        lock.lock()
        _preferredVideoItags = itags
        lock.unlock()
    }

    static let preferredAudioItags = [140, 141, 139]
}

struct HttpStringResult: Sendable {
    var success: Bool
    var body: String
    var errCode: Int
    var errMsg: String

    /// URLSession / Swift concurrency cancellation — must not clear UI or force reauth.
    var isCancellation: Bool {
        if errCode == URLError.cancelled.rawValue { return true }
        let lower = errMsg.lowercased()
        if lower == "cancelled" || lower.contains("cancel") { return true }
        return false
    }
}

enum ChannelAvatarFetcher {
    /// YouTube Data API `channels.list` — used when extract/queue has no avatar.
    static func fetch(channelId: String, apiKey: String) async -> URL? {
        guard ChannelID.isBrowsable(channelId), !apiKey.isEmpty else { return nil }
        var comps = URLComponents(string: "https://www.googleapis.com/youtube/v3/channels")
        comps?.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "id", value: channelId),
            URLQueryItem(name: "key", value: apiKey),
        ]
        guard let url = comps?.url else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]],
                  let snippet = items.first?["snippet"] as? [String: Any],
                  let thumbs = snippet["thumbnails"] as? [String: Any]
            else { return nil }
            for key in ["high", "medium", "default"] {
                if let t = thumbs[key] as? [String: Any],
                   let s = t["url"] as? String,
                   let u = URL(string: s) {
                    return u
                }
            }
            return nil
        } catch {
            return nil
        }
    }
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
        // YouTube Data API / InnerTube must not reuse stale likes/playlist responses.
        request.cachePolicy = .reloadIgnoringLocalCacheData
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
        } catch let error as URLError where error.code == .cancelled {
            return HttpStringResult(
                success: false,
                body: "",
                errCode: URLError.cancelled.rawValue,
                errMsg: "cancelled"
            )
        } catch {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain, ns.code == URLError.cancelled.rawValue {
                return HttpStringResult(
                    success: false,
                    body: "",
                    errCode: URLError.cancelled.rawValue,
                    errMsg: "cancelled"
                )
            }
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
