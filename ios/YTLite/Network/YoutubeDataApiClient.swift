import Foundation

/// YouTube Data API v3 client for the Subs / You tab (Android `YoutubeDataApiClient` subset).
/// Requires OAuth access token with `youtube.readonly` + a Data API key.
enum YoutubeDataApiClient {
    private static let base = "https://www.googleapis.com/youtube/v3"
    private static let previewCount = 12

    struct SubscriptionChannel: Identifiable, Hashable, Sendable {
        var id: String { channelId }
        let channelId: String
        let title: String
        let avatarUrl: String?
        let description: String?

        var asChannelItem: ChannelItem {
            ChannelItem(
                channelId: channelId,
                title: title,
                subtitle: "Channel",
                thumbnailURL: avatarUrl.flatMap(URL.init(string:))
            )
        }
    }

    struct PlaylistPreview: Identifiable, Hashable, Sendable {
        var id: String { playlistId }
        let playlistId: String
        let title: String
        let thumbnailUrl: String?
        let itemCount: Int?
    }

    struct YouPageSnapshot: Sendable {
        var subscriptions: [SubscriptionChannel]
        var playlists: [PlaylistPreview]
        var liked: [VideoItem]
        var likedPlaylistId: String?
        var needsYoutubeReauth: Bool
        var errorMessage: String?
    }

    static func loadYouPage(
        oauthAccessToken: String?,
        apiKey: String
    ) async -> YouPageSnapshot {
        guard !apiKey.isEmpty else {
            return YouPageSnapshot(
                subscriptions: [],
                playlists: [],
                liked: [],
                likedPlaylistId: nil,
                needsYoutubeReauth: false,
                errorMessage: "YouTube Data API key is not configured"
            )
        }
        guard let token = oauthAccessToken, !token.isEmpty else {
            return YouPageSnapshot(
                subscriptions: [],
                playlists: [],
                liked: [],
                likedPlaylistId: nil,
                needsYoutubeReauth: true,
                errorMessage: nil
            )
        }

        async let subs = listSubscriptions(token: token, apiKey: apiKey)
        async let related = fetchMineRelatedPlaylists(token: token, apiKey: apiKey)
        async let playlists = listCustomPlaylists(token: token, apiKey: apiKey)

        let subsResult = await subs
        let relatedMap = await related
        let playlistResult = await playlists
        let likesId = relatedMap?["likes"] ?? relatedMap?["favorites"]

        var liked: [VideoItem] = []
        if let likesId, !likesId.isEmpty {
            liked = await listPlaylistItems(token: token, apiKey: apiKey, playlistId: likesId) ?? []
        }

        let unauthorized = subsResult.unauthorized
            || playlistResult.unauthorized
            || (relatedMap == nil && likesId == nil && subsResult.channels.isEmpty)

        return YouPageSnapshot(
            subscriptions: subsResult.channels,
            playlists: playlistResult.playlists,
            liked: liked,
            likedPlaylistId: likesId,
            needsYoutubeReauth: unauthorized && subsResult.channels.isEmpty
                && playlistResult.playlists.isEmpty && liked.isEmpty,
            errorMessage: nil
        )
    }

    static func listPlaylistItems(
        token: String,
        apiKey: String,
        playlistId: String,
        maxResults: Int = 50
    ) async -> [VideoItem]? {
        var comps = URLComponents(string: "\(base)/playlistItems")
        comps?.queryItems = [
            URLQueryItem(name: "part", value: "snippet,contentDetails"),
            URLQueryItem(name: "playlistId", value: playlistId),
            URLQueryItem(name: "maxResults", value: String(min(50, maxResults))),
            URLQueryItem(name: "key", value: apiKey),
        ]
        guard let url = comps?.url?.absoluteString else { return nil }
        let result = await YouTubeHTTPClient.shared.request(
            url: url,
            method: "GET",
            headers: [
                "Authorization": "Bearer \(token)",
                "Accept": "application/json",
            ],
            body: nil
        )
        guard result.success,
              let data = result.body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]]
        else { return nil }

        return items.compactMap { item -> VideoItem? in
            let snippet = item["snippet"] as? [String: Any]
            let videoId = (snippet?["resourceId"] as? [String: Any])?["videoId"] as? String
            guard let videoId, !videoId.isEmpty else { return nil }
            let title = snippet?["title"] as? String ?? videoId
            if title == "Private video" || title == "Deleted video" { return nil }
            let channel = snippet?["channelTitle"] as? String ?? ""
            let thumbs = snippet?["thumbnails"] as? [String: Any]
            let thumb = (thumbs?["high"] as? [String: Any])?["url"] as? String
                ?? (thumbs?["medium"] as? [String: Any])?["url"] as? String
                ?? (thumbs?["default"] as? [String: Any])?["url"] as? String
            return VideoItem(
                videoId: videoId,
                title: title,
                channelName: channel,
                thumbnailURL: thumb.flatMap(URL.init(string:))
            )
        }
    }

    // MARK: - Private

    private struct ChannelListResult {
        var channels: [SubscriptionChannel]
        var unauthorized: Bool
    }

    private struct PlaylistListResult {
        var playlists: [PlaylistPreview]
        var unauthorized: Bool
    }

    private static func listSubscriptions(token: String, apiKey: String) async -> ChannelListResult {
        var comps = URLComponents(string: "\(base)/subscriptions")
        comps?.queryItems = [
            URLQueryItem(name: "part", value: "snippet,contentDetails"),
            URLQueryItem(name: "mine", value: "true"),
            URLQueryItem(name: "maxResults", value: String(previewCount)),
            URLQueryItem(name: "key", value: apiKey),
        ]
        guard let url = comps?.url?.absoluteString else {
            return ChannelListResult(channels: [], unauthorized: false)
        }
        let result = await YouTubeHTTPClient.shared.request(
            url: url,
            method: "GET",
            headers: [
                "Authorization": "Bearer \(token)",
                "Accept": "application/json",
            ],
            body: nil
        )
        if result.errCode == 401 || result.errCode == 403 {
            return ChannelListResult(channels: [], unauthorized: true)
        }
        guard result.success,
              let data = result.body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]]
        else {
            return ChannelListResult(channels: [], unauthorized: false)
        }
        let channels: [SubscriptionChannel] = items.compactMap { item in
            guard let snippet = item["snippet"] as? [String: Any],
                  let resourceId = snippet["resourceId"] as? [String: Any],
                  let channelId = resourceId["channelId"] as? String, !channelId.isEmpty,
                  let title = snippet["title"] as? String, !title.isEmpty
            else { return nil }
            let thumbs = snippet["thumbnails"] as? [String: Any]
            let avatar = (thumbs?["medium"] as? [String: Any])?["url"] as? String
                ?? (thumbs?["default"] as? [String: Any])?["url"] as? String
            let description = (snippet["description"] as? String)?.nilIfEmpty
            return SubscriptionChannel(
                channelId: channelId,
                title: title,
                avatarUrl: avatar,
                description: description
            )
        }
        return ChannelListResult(channels: channels, unauthorized: false)
    }

    private static func fetchMineRelatedPlaylists(token: String, apiKey: String) async -> [String: String]? {
        var comps = URLComponents(string: "\(base)/channels")
        comps?.queryItems = [
            URLQueryItem(name: "part", value: "contentDetails"),
            URLQueryItem(name: "mine", value: "true"),
            URLQueryItem(name: "maxResults", value: "1"),
            URLQueryItem(name: "key", value: apiKey),
        ]
        guard let url = comps?.url?.absoluteString else { return nil }
        let result = await YouTubeHTTPClient.shared.request(
            url: url,
            method: "GET",
            headers: [
                "Authorization": "Bearer \(token)",
                "Accept": "application/json",
            ],
            body: nil
        )
        guard result.success,
              let data = result.body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]],
              let first = items.first,
              let related = (first["contentDetails"] as? [String: Any])?["relatedPlaylists"] as? [String: String]
        else { return nil }
        return related
    }

    private static func listCustomPlaylists(token: String, apiKey: String) async -> PlaylistListResult {
        var comps = URLComponents(string: "\(base)/playlists")
        comps?.queryItems = [
            URLQueryItem(name: "part", value: "snippet,contentDetails"),
            URLQueryItem(name: "mine", value: "true"),
            URLQueryItem(name: "maxResults", value: String(previewCount)),
            URLQueryItem(name: "key", value: apiKey),
        ]
        guard let url = comps?.url?.absoluteString else {
            return PlaylistListResult(playlists: [], unauthorized: false)
        }
        let result = await YouTubeHTTPClient.shared.request(
            url: url,
            method: "GET",
            headers: [
                "Authorization": "Bearer \(token)",
                "Accept": "application/json",
            ],
            body: nil
        )
        if result.errCode == 401 || result.errCode == 403 {
            return PlaylistListResult(playlists: [], unauthorized: true)
        }
        guard result.success,
              let data = result.body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]]
        else {
            return PlaylistListResult(playlists: [], unauthorized: false)
        }
        let playlists: [PlaylistPreview] = items.compactMap { item in
            guard let playlistId = item["id"] as? String, !playlistId.isEmpty,
                  let snippet = item["snippet"] as? [String: Any],
                  let title = snippet["title"] as? String, !title.isEmpty
            else { return nil }
            // Skip system playlists if they appear here.
            if playlistId == "LL" || playlistId == "WL" || playlistId == "HL" { return nil }
            let thumbs = snippet["thumbnails"] as? [String: Any]
            let thumb = (thumbs?["high"] as? [String: Any])?["url"] as? String
                ?? (thumbs?["medium"] as? [String: Any])?["url"] as? String
                ?? (thumbs?["default"] as? [String: Any])?["url"] as? String
            let countStr = (item["contentDetails"] as? [String: Any])?["itemCount"] as? String
            let count = countStr.flatMap(Int.init)
                ?? (item["contentDetails"] as? [String: Any])?["itemCount"] as? Int
            return PlaylistPreview(
                playlistId: playlistId,
                title: title,
                thumbnailUrl: thumb,
                itemCount: count
            )
        }
        return PlaylistListResult(playlists: playlists, unauthorized: false)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
