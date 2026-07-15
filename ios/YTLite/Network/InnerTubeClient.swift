import Foundation

enum InnerTubeClient {
    static let browseURL = "\(YouTubeConstants.baseURL)/youtubei/v1/browse?key=\(YouTubeConstants.apiKey)"
    static let homeBrowseId = "FEwhat_to_watch"

    static func searchVideos(query: String) async throws -> [VideoItem] {
        try await search(query: query, tab: .videos).compactMap(\.asVideoItem)
    }

    /// Tabbed search matching Android `SearchRepository.search`.
    static func search(query: String, tab: SearchResultTab) async throws -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var body: [String: Any] = [
            "context": clientContext(),
            "query": trimmed,
        ]
        if let params = tab.innerTubeParams {
            body["params"] = params
        }
        let json = try await postJSON(url: YouTubeConstants.searchURL, body: body, label: "search_\(tab.rawValue)")
        return VideoJSONParser.parseSearchHits(from: json, tab: tab)
    }

    /// Google Suggest autocomplete for YouTube (`ds=yt`), same as Android `fetchSuggestQueries`.
    static func fetchSuggestQueries(query: String) async -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
        let url =
            "https://suggestqueries.google.com/complete/search?client=firefox&ds=yt&q=\(encoded)"
        let result = await YouTubeHTTPClient.shared.request(
            url: url,
            method: "GET",
            headers: [
                "User-Agent": YouTubeConstants.userAgent,
                "Accept": "application/json",
            ],
            body: nil
        )
        guard result.success,
              let data = result.body.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              root.count > 1
        else { return [] }

        let items: [Any]
        if let arr = root[1] as? [Any] {
            items = arr
        } else {
            return []
        }

        return items.compactMap { entry -> String? in
            if let s = entry as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }
            // Some payloads nest [query, rank, ...]
            if let arr = entry as? [Any], let s = arr.first as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }
            return nil
        }
    }

    static func fetchHomeFeed() async throws -> [VideoItem] {
        let body: [String: Any] = [
            "context": clientContext(),
            "browseId": homeBrowseId,
        ]
        let json = try await postJSON(url: browseURL, body: body, label: "home")
        let videos = VideoJSONParser.parseVideos(from: json)
        if !videos.isEmpty { return videos }
        return try await searchVideos(query: "music")
    }

    static func searchChannels(query: String) async throws -> [ChannelItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let body: [String: Any] = [
            "context": clientContext(),
            "query": trimmed,
            "params": "EgIQAg%3D%3D",
        ]
        let json = try await postJSON(url: YouTubeConstants.searchURL, body: body, label: "search_channels")
        return VideoJSONParser.parseChannels(from: json)
    }

    static func searchPlaylists(query: String) async throws -> [PlaylistPreview] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let body: [String: Any] = [
            "context": clientContext(),
            "query": trimmed,
            "params": "EgIQAw%3D%3D",
        ]
        let json = try await postJSON(url: YouTubeConstants.searchURL, body: body, label: "search_playlists")
        return VideoJSONParser.parsePlaylists(from: json)
    }

    /// Channel uploads via UU… playlist (public InnerTube).
    static func fetchChannelUploads(channelId: String) async throws -> [VideoItem] {
        guard channelId.hasPrefix("UC"), channelId.count > 2 else { return [] }
        let uploadsId = "UU" + channelId.dropFirst(2)
        return try await fetchPlaylistVideos(playlistId: String(uploadsId))
    }

    static func fetchPlaylistVideos(playlistId: String) async throws -> [VideoItem] {
        let browseId = playlistId.hasPrefix("VL") ? playlistId : "VL\(playlistId)"
        let body: [String: Any] = [
            "context": clientContext(),
            "browseId": browseId,
        ]
        let json = try await postJSON(url: browseURL, body: body, label: "playlist")
        return VideoJSONParser.parseVideos(from: json)
    }

    static func fetchTrendingMusic(apiKey: String) async throws -> [VideoItem] {
        guard !apiKey.isEmpty else {
            return try await searchVideos(query: "music")
        }
        let url =
            "https://www.googleapis.com/youtube/v3/videos?part=snippet,contentDetails&chart=mostPopular&videoCategoryId=10&maxResults=20&key=\(apiKey)"
        let result = await YouTubeHTTPClient.shared.request(
            url: url,
            method: "GET",
            headers: ["Accept": "application/json"],
            body: nil
        )
        guard result.success,
              let data = result.body.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]]
        else {
            return try await searchVideos(query: "music")
        }
        return items.compactMap { item in
            guard let id = item["id"] as? String,
                  let snippet = item["snippet"] as? [String: Any]
            else { return nil }
            let title = snippet["title"] as? String ?? id
            let channel = snippet["channelTitle"] as? String ?? ""
            let thumbs = snippet["thumbnails"] as? [String: Any]
            let high = (thumbs?["high"] as? [String: Any])?["url"] as? String
            let iso = (item["contentDetails"] as? [String: Any])?["duration"] as? String
            return VideoItem(
                videoId: id,
                title: title,
                channelName: channel,
                thumbnailURL: high.flatMap(URL.init(string:)),
                durationText: DurationFormat.text(fromISO8601: iso)
            )
        }
    }

    private static func clientContext() -> [String: Any] {
        [
            "client": [
                "clientName": YouTubeConstants.webClientName,
                "clientVersion": YouTubeConstants.webClientVersion,
                "hl": YouTubeConstants.hl,
                "gl": YouTubeConstants.gl,
            ],
        ]
    }

    private static func postJSON(url: String, body: [String: Any], label: String) async throws -> Any {
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let bodyString = String(data: bodyData, encoding: .utf8) ?? "{}"
        let result = await YouTubeHTTPClient.shared.request(
            url: url,
            method: "POST",
            headers: [
                "User-Agent": YouTubeConstants.userAgent,
                "Content-Type": "application/json",
                "X-YouTube-Client-Name": YouTubeConstants.webClientNameHeader,
                "X-YouTube-Client-Version": YouTubeConstants.webClientVersion,
                "Origin": YouTubeConstants.baseURL,
            ],
            body: bodyString
        )
        guard result.success, let data = result.body.data(using: .utf8) else {
            throw ExtractorBridge.ExtractorError.extractFailed(
                result.errMsg.isEmpty ? "\(label) failed" : result.errMsg
            )
        }
        return try JSONSerialization.jsonObject(with: data)
    }
}

enum VideoJSONParser {
    static func parseVideos(from root: Any) -> [VideoItem] {
        var items: [String: VideoItem] = [:]
        var queue: [Any] = [root]
        var visited = 0
        while !queue.isEmpty && visited < 8_000 {
            let node = queue.removeFirst()
            visited += 1
            if let dict = node as? [String: Any] {
                if isAd(dict) { continue }
                if let item = extractVideo(from: dict) {
                    items[item.videoId] = item
                }
                for value in dict.values where value is [String: Any] || value is [Any] {
                    queue.append(value)
                }
            } else if let array = node as? [Any] {
                for value in array where value is [String: Any] || value is [Any] {
                    queue.append(value)
                }
            }
        }
        return Array(items.values)
    }

    static func parseSearchHits(from root: Any, tab: SearchResultTab) -> [SearchHit] {
        var hits: [SearchHit] = []
        var seen = Set<String>()
        walk(root) { dict in
            if isAd(dict) { return }
            switch tab {
            case .all:
                if let v = extractVideo(from: dict) {
                    let id = "v:\(v.videoId)"
                    if seen.insert(id).inserted { hits.append(.video(v)) }
                } else if let c = extractChannel(from: dict) {
                    let id = "c:\(c.channelId)"
                    if seen.insert(id).inserted { hits.append(.channel(c)) }
                } else if let p = extractPlaylist(from: dict) {
                    let id = "p:\(p.playlistId)"
                    if seen.insert(id).inserted { hits.append(.playlist(p)) }
                }
            case .videos:
                if let v = extractVideo(from: dict) {
                    let id = "v:\(v.videoId)"
                    if seen.insert(id).inserted { hits.append(.video(v)) }
                }
            case .channels:
                if let c = extractChannel(from: dict) {
                    let id = "c:\(c.channelId)"
                    if seen.insert(id).inserted { hits.append(.channel(c)) }
                }
            case .playlists:
                if let p = extractPlaylist(from: dict) {
                    let id = "p:\(p.playlistId)"
                    if seen.insert(id).inserted { hits.append(.playlist(p)) }
                }
            }
        }
        return hits
    }

    static func parseChannels(from root: Any) -> [ChannelItem] {
        var items: [String: ChannelItem] = [:]
        walk(root) { dict in
            if let item = extractChannel(from: dict) {
                items[item.channelId] = item
            }
        }
        return Array(items.values)
    }

    static func parsePlaylists(from root: Any) -> [PlaylistPreview] {
        var items: [String: PlaylistPreview] = [:]
        walk(root) { dict in
            if let item = extractPlaylist(from: dict) {
                items[item.playlistId] = item
            }
        }
        return Array(items.values)
    }

    private static func walk(_ root: Any, visit: ([String: Any]) -> Void) {
        var queue: [Any] = [root]
        var visited = 0
        while !queue.isEmpty && visited < 8_000 {
            let node = queue.removeFirst()
            visited += 1
            if let dict = node as? [String: Any] {
                visit(dict)
                for value in dict.values where value is [String: Any] || value is [Any] {
                    queue.append(value)
                }
            } else if let array = node as? [Any] {
                for value in array where value is [String: Any] || value is [Any] {
                    queue.append(value)
                }
            }
        }
    }

    private static func extractChannel(from node: [String: Any]) -> ChannelItem? {
        let renderer = (node["channelRenderer"] as? [String: Any])
            ?? (node["gridChannelRenderer"] as? [String: Any])
        guard let renderer else { return nil }
        let channelId = (renderer["channelId"] as? String)?.nilIfEmpty
            ?? (renderer["browseId"] as? String)?.nilIfEmpty
        guard let channelId else { return nil }
        let title = extractText(renderer["title"]) ?? channelId
        let handle = extractText(renderer["channelHandle"])
            ?? extractText(renderer["subscriberCountText"])
            ?? extractText(renderer["videoCountText"])
            ?? ""
        let subtitle: String = {
            if handle.hasPrefix("@") { return handle }
            if handle.contains("subscriber") || handle.contains("video") { return handle }
            if !handle.isEmpty { return "@\(handle)" }
            return ""
        }()
        let thumb = pickThumbnail(renderer["thumbnail"] as? [String: Any])
        return ChannelItem(
            channelId: channelId,
            title: title,
            subtitle: subtitle,
            thumbnailURL: thumb
        )
    }

    private static func extractPlaylist(from node: [String: Any]) -> PlaylistPreview? {
        let renderer = (node["playlistRenderer"] as? [String: Any])
            ?? (node["gridPlaylistRenderer"] as? [String: Any])
        guard let renderer,
              let playlistId = renderer["playlistId"] as? String,
              !playlistId.isEmpty
        else { return nil }
        let title = extractText(renderer["title"]) ?? playlistId
        let subtitle = extractText(renderer["shortBylineText"])
            ?? extractText(renderer["videoCountText"])
            ?? ""
        let thumb = pickThumbnail(renderer["thumbnails"] as? [String: Any])
            ?? pickThumbnail((renderer["thumbnail"] as? [String: Any]))
        return PlaylistPreview(
            playlistId: playlistId,
            title: title,
            subtitle: subtitle,
            thumbnailURL: thumb
        )
    }

    private static func isAd(_ node: [String: Any]) -> Bool {
        let keys = [
            "adVideoRenderer", "promotedSparklesWebRenderer", "displayAdRenderer",
            "promotedVideoRenderer", "compactPromotedVideoRenderer",
        ]
        return keys.contains { node[$0] != nil }
    }

    private static func extractVideo(from node: [String: Any]) -> VideoItem? {
        let renderer = (node["videoRenderer"] as? [String: Any])
            ?? (node["gridVideoRenderer"] as? [String: Any])
            ?? (node["compactVideoRenderer"] as? [String: Any])
        guard let renderer,
              let videoId = renderer["videoId"] as? String,
              !videoId.isEmpty
        else { return nil }
        let title = extractText(renderer["title"]) ?? videoId
        let channel = extractText(renderer["ownerText"])
            ?? extractText(renderer["shortBylineText"])
            ?? ""
        let views = extractText(renderer["shortViewCountText"])
            ?? extractText(renderer["viewCountText"])
        let published = extractText(renderer["publishedTimeText"])
        let parts = [channel, views, published].compactMap { $0 }.filter { !$0.isEmpty }
        let thumb = pickThumbnail(renderer["thumbnail"] as? [String: Any])
        let duration = extractText(renderer["lengthText"])
            ?? lengthFromOverlays(renderer["thumbnailOverlays"] as? [[String: Any]])
        return VideoItem(
            videoId: videoId,
            title: title,
            channelName: channel,
            subtitle: parts.joined(separator: " · "),
            thumbnailURL: thumb,
            durationText: duration
        )
    }

    private static func lengthFromOverlays(_ overlays: [[String: Any]]?) -> String? {
        guard let overlays else { return nil }
        for overlay in overlays {
            if let renderer = overlay["thumbnailOverlayTimeStatusRenderer"] as? [String: Any] {
                return extractText(renderer["text"])
            }
        }
        return nil
    }

    private static func extractText(_ any: Any?) -> String? {
        if let s = any as? String { return s }
        guard let dict = any as? [String: Any] else { return nil }
        if let simple = dict["simpleText"] as? String { return simple }
        if let runs = dict["runs"] as? [[String: Any]] {
            let text = runs.compactMap { $0["text"] as? String }.joined()
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private static func pickThumbnail(_ thumb: [String: Any]?) -> URL? {
        guard let thumbs = thumb?["thumbnails"] as? [[String: Any]] else { return nil }
        return thumbs.reversed().compactMap { ($0["url"] as? String).flatMap(URL.init(string:)) }.first
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct ChannelItem: Identifiable, Hashable, Sendable {
    var id: String { channelId }
    let channelId: String
    let title: String
    let subtitle: String
    let thumbnailURL: URL?
}

struct PlaylistPreview: Identifiable, Hashable, Sendable {
    var id: String { playlistId }
    let playlistId: String
    let title: String
    let subtitle: String
    let thumbnailURL: URL?
}
