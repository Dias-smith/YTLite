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
        /// Pull-to-refresh / task cancellation — caller must keep previous UI state.
        var wasCancelled: Bool = false
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
        async let owned = fetchOwnedChannelsWithRelated(token: token, apiKey: apiKey)

        let subsResult = await subs
        let ownedResult = await owned

        if Task.isCancelled || subsResult.cancelled || ownedResult.cancelled {
            return YouPageSnapshot(
                subscriptions: [],
                playlists: [],
                liked: [],
                likedPlaylistId: nil,
                needsYoutubeReauth: false,
                errorMessage: nil,
                wasCancelled: true
            )
        }

        let related = ownedResult.channels.first?.relatedPlaylists ?? [:]
        let relatedIds = Set(ownedResult.channels.flatMap(\.relatedPlaylists.values))
        let likesId = related["likes"] ?? related["favorites"] ?? "LL"

        async let playlists = listCustomPlaylists(
            token: token,
            apiKey: apiKey,
            ownedChannels: ownedResult.channels,
            relatedIds: relatedIds
        )
        async let likedTask = listPlaylistItemsResult(token: token, apiKey: apiKey, playlistId: likesId)

        var playlistResult = await playlists
        let likedHttp = await likedTask

        if Task.isCancelled || playlistResult.cancelled || likedHttp.cancelled {
            return YouPageSnapshot(
                subscriptions: [],
                playlists: [],
                liked: [],
                likedPlaylistId: nil,
                needsYoutubeReauth: false,
                errorMessage: nil,
                wasCancelled: true
            )
        }

        var liked = likedHttp.items ?? []

        // Data API search.list forMine — often finds playlists that playlists.list misses.
        if playlistResult.playlists.isEmpty, !playlistResult.unauthorized {
            let viaSearch = await listPlaylistsViaSearchForMine(token: token, apiKey: apiKey)
            if viaSearch.cancelled {
                return YouPageSnapshot(
                    subscriptions: [],
                    playlists: [],
                    liked: [],
                    likedPlaylistId: nil,
                    needsYoutubeReauth: false,
                    errorMessage: nil,
                    wasCancelled: true
                )
            }
            if !viaSearch.playlists.isEmpty {
                playlistResult = viaSearch
            }
        }

        // InnerTube fallback (Bearer OAuth) for playlists / liked.
        if playlistResult.playlists.isEmpty, !playlistResult.unauthorized {
            let innerPlaylists = await InnerTubeClient.browseLibraryPlaylists(oauthAccessToken: token)
            if !innerPlaylists.isEmpty {
                playlistResult = PlaylistListResult(
                    playlists: innerPlaylists,
                    unauthorized: false,
                    failed: false,
                    error: nil
                )
            }
        }
        if liked.isEmpty, !likedHttp.unauthorized {
            let innerLiked = await InnerTubeClient.browseLikedVideos(oauthAccessToken: token)
            if !innerLiked.isEmpty {
                liked = innerLiked
            }
        }

        let unauthorized = subsResult.unauthorized
            || ownedResult.unauthorized
            || playlistResult.unauthorized
            || likedHttp.unauthorized

        let errorBits = [subsResult.error, ownedResult.error, playlistResult.error]
            .compactMap { $0 }
            .filter { !isIgnorableChannelLookupError($0) && !$0.lowercased().contains("cancel") }
        let errorMessage = unauthorized ? nil : errorBits.first

        return YouPageSnapshot(
            subscriptions: subsResult.channels,
            playlists: playlistResult.playlists,
            liked: liked,
            likedPlaylistId: likesId,
            // Only real auth failures — never empty/cancel/network-only.
            needsYoutubeReauth: unauthorized,
            errorMessage: errorMessage
        )
    }

    private struct PlaylistItemsResult {
        var items: [VideoItem]?
        var unauthorized: Bool
        var cancelled: Bool
    }

    private static func listPlaylistItemsResult(
        token: String,
        apiKey: String,
        playlistId: String,
        maxResults: Int = 50
    ) async -> PlaylistItemsResult {
        var comps = URLComponents(string: "\(base)/playlistItems")
        comps?.queryItems = [
            URLQueryItem(name: "part", value: "snippet,contentDetails"),
            URLQueryItem(name: "playlistId", value: playlistId),
            URLQueryItem(name: "maxResults", value: String(min(50, maxResults))),
            URLQueryItem(name: "key", value: apiKey),
        ]
        guard let url = comps?.url?.absoluteString else {
            return PlaylistItemsResult(items: nil, unauthorized: false, cancelled: false)
        }
        let result = await YouTubeHTTPClient.shared.request(
            url: url,
            method: "GET",
            headers: authHeaders(token),
            body: nil
        )
        if result.isCancellation {
            return PlaylistItemsResult(items: nil, unauthorized: false, cancelled: true)
        }
        if result.errCode == 401 || result.errCode == 403 {
            return PlaylistItemsResult(items: nil, unauthorized: true, cancelled: false)
        }
        guard result.success,
              let data = result.body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]]
        else {
            return PlaylistItemsResult(items: nil, unauthorized: false, cancelled: false)
        }
        let videos: [VideoItem] = items.compactMap { item -> VideoItem? in
            let snippet = item["snippet"] as? [String: Any]
            let videoId = (snippet?["resourceId"] as? [String: Any])?["videoId"] as? String
                ?? (item["contentDetails"] as? [String: Any])?["videoId"] as? String
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
        return PlaylistItemsResult(items: videos, unauthorized: false, cancelled: false)
    }

    static func listPlaylistItems(
        token: String,
        apiKey: String,
        playlistId: String,
        maxResults: Int = 50
    ) async -> [VideoItem]? {
        await listPlaylistItemsResult(
            token: token,
            apiKey: apiKey,
            playlistId: playlistId,
            maxResults: maxResults
        ).items
    }

    // MARK: - Private

    private struct OwnedChannel {
        let channelId: String
        let title: String
        let relatedPlaylists: [String: String]
    }

    private struct ChannelListResult {
        var channels: [SubscriptionChannel]
        var unauthorized: Bool
        var error: String?
        var cancelled: Bool = false
    }

    private struct OwnedChannelsResult {
        var channels: [OwnedChannel]
        var unauthorized: Bool
        var failed: Bool
        var error: String?
        var cancelled: Bool = false
    }

    private struct PlaylistListResult {
        var playlists: [PlaylistPreview]
        var unauthorized: Bool
        var failed: Bool
        var error: String?
        var cancelled: Bool = false
    }

    private static func authHeaders(_ token: String) -> [String: String] {
        [
            "Authorization": "Bearer \(token)",
            "Accept": "application/json",
        ]
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
            return ChannelListResult(channels: [], unauthorized: false, error: "Invalid URL")
        }
        let result = await YouTubeHTTPClient.shared.request(
            url: url,
            method: "GET",
            headers: authHeaders(token),
            body: nil
        )
        if result.isCancellation {
            return ChannelListResult(channels: [], unauthorized: false, error: nil, cancelled: true)
        }
        if result.errCode == 401 || result.errCode == 403 {
            return ChannelListResult(
                channels: [],
                unauthorized: true,
                error: apiErrorMessage(from: result.body) ?? "YouTube authorization failed"
            )
        }
        guard result.success,
              let data = result.body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]]
        else {
            return ChannelListResult(
                channels: [],
                unauthorized: false,
                error: apiErrorMessage(from: result.body) ?? result.errMsg.nilIfEmpty
            )
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
        return ChannelListResult(channels: channels, unauthorized: false, error: nil)
    }

    /// Android `fetchChannelsWithRelatedPlaylists` — `channels.list?mine=true&part=snippet,contentDetails`.
    private static func fetchOwnedChannelsWithRelated(token: String, apiKey: String) async -> OwnedChannelsResult {
        var comps = URLComponents(string: "\(base)/channels")
        comps?.queryItems = [
            URLQueryItem(name: "part", value: "snippet,contentDetails"),
            URLQueryItem(name: "mine", value: "true"),
            URLQueryItem(name: "maxResults", value: "50"),
            URLQueryItem(name: "key", value: apiKey),
        ]
        guard let url = comps?.url?.absoluteString else {
            return OwnedChannelsResult(channels: [], unauthorized: false, failed: true, error: "Invalid URL")
        }
        let result = await YouTubeHTTPClient.shared.request(
            url: url,
            method: "GET",
            headers: authHeaders(token),
            body: nil
        )
        if result.isCancellation {
            return OwnedChannelsResult(
                channels: [],
                unauthorized: false,
                failed: false,
                error: nil,
                cancelled: true
            )
        }
        if result.errCode == 401 || result.errCode == 403 {
            return OwnedChannelsResult(
                channels: [],
                unauthorized: true,
                failed: true,
                error: apiErrorMessage(from: result.body) ?? "YouTube authorization failed"
            )
        }
        guard result.success,
              let data = result.body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]]
        else {
            return OwnedChannelsResult(
                channels: [],
                unauthorized: false,
                failed: true,
                error: apiErrorMessage(from: result.body) ?? result.errMsg.nilIfEmpty
            )
        }

        let channels: [OwnedChannel] = items.compactMap { item in
            guard let channelId = item["id"] as? String, !channelId.isEmpty else { return nil }
            let title = (item["snippet"] as? [String: Any])?["title"] as? String ?? ""
            var related: [String: String] = [:]
            if let relatedObj = (item["contentDetails"] as? [String: Any])?["relatedPlaylists"] as? [String: Any] {
                for (key, value) in relatedObj {
                    if let id = value as? String, !id.isEmpty {
                        related[key] = id
                    }
                }
            }
            return OwnedChannel(channelId: channelId, title: title, relatedPlaylists: related)
        }
        return OwnedChannelsResult(channels: channels, unauthorized: false, failed: false, error: nil)
    }

    /// Prefer `playlists.list?mine=true` (includes private). Optionally merge public
    /// playlists from owned `channelId`s. Ignore “Channel not found” from channelId lookups —
    /// that 404 is common for some brand/handle channels and must not block `mine=true`.
    private static func listCustomPlaylists(
        token: String,
        apiKey: String,
        ownedChannels: [OwnedChannel],
        relatedIds: Set<String>
    ) async -> PlaylistListResult {
        var collected: [String: PlaylistPreview] = [:]

        let mine = await listPlaylistsMine(token: token, apiKey: apiKey)
        if mine.cancelled {
            return PlaylistListResult(
                playlists: [],
                unauthorized: false,
                failed: false,
                error: nil,
                cancelled: true
            )
        }
        for playlist in mine.playlists where isCustomPlaylist(playlist.playlistId, relatedIds: relatedIds) {
            collected[playlist.playlistId] = playlist
        }

        // Soft-enrich from channelId (Android multi-channel); never let 404 override mine results.
        if collected.count < previewCount, !ownedChannels.isEmpty {
            for channel in ownedChannels {
                let page = await listPlaylistsByChannelId(
                    token: token,
                    apiKey: apiKey,
                    channelId: channel.channelId
                )
                if page.unauthorized { continue }
                if isIgnorableChannelLookupError(page.error) { continue }
                for playlist in page.playlists where isCustomPlaylist(playlist.playlistId, relatedIds: relatedIds) {
                    collected[playlist.playlistId] = playlist
                }
                if collected.count >= previewCount { break }
            }
        }

        let playlists = Array(collected.values.prefix(previewCount))
        // Only surface mine=true auth/transport errors — not channelId “Channel not found”.
        let error: String?
        if playlists.isEmpty {
            if mine.unauthorized {
                error = mine.error
            } else if mine.failed, !isIgnorableChannelLookupError(mine.error) {
                error = mine.error
            } else {
                error = nil
            }
        } else {
            error = nil
        }

        return PlaylistListResult(
            playlists: playlists,
            unauthorized: mine.unauthorized && playlists.isEmpty,
            failed: playlists.isEmpty && mine.failed,
            error: error
        )
    }

    private static func isIgnorableChannelLookupError(_ message: String?) -> Bool {
        guard let message, !message.isEmpty else { return false }
        let lower = message.lowercased()
        return lower.contains("channel not found")
            || lower.contains("playlist not found")
            || lower.contains("notFound")
    }

    private static func isCustomPlaylist(_ playlistId: String, relatedIds: Set<String>) -> Bool {
        if relatedIds.contains(playlistId) { return false }
        if playlistId == "WL" || playlistId == "LL" || playlistId == "HL" { return false }
        if playlistId.hasPrefix("UU"), playlistId.count > 2 { return false }
        return true
    }

    private static func listPlaylistsByChannelId(
        token: String,
        apiKey: String,
        channelId: String
    ) async -> PlaylistListResult {
        var comps = URLComponents(string: "\(base)/playlists")
        comps?.queryItems = [
            URLQueryItem(name: "part", value: "snippet,contentDetails"),
            URLQueryItem(name: "channelId", value: channelId),
            URLQueryItem(name: "maxResults", value: String(previewCount)),
            URLQueryItem(name: "key", value: apiKey),
        ]
        return await parsePlaylistsResponse(
            url: comps?.url?.absoluteString,
            token: token
        )
    }

    private static func listPlaylistsMine(token: String, apiKey: String) async -> PlaylistListResult {
        var comps = URLComponents(string: "\(base)/playlists")
        comps?.queryItems = [
            URLQueryItem(name: "part", value: "snippet,contentDetails"),
            URLQueryItem(name: "mine", value: "true"),
            URLQueryItem(name: "maxResults", value: String(previewCount)),
            URLQueryItem(name: "key", value: apiKey),
        ]
        return await parsePlaylistsResponse(
            url: comps?.url?.absoluteString,
            token: token
        )
    }

    private static func parsePlaylistsResponse(url: String?, token: String) async -> PlaylistListResult {
        guard let url else {
            return PlaylistListResult(playlists: [], unauthorized: false, failed: true, error: "Invalid URL")
        }
        let result = await YouTubeHTTPClient.shared.request(
            url: url,
            method: "GET",
            headers: authHeaders(token),
            body: nil
        )
        if result.isCancellation {
            return PlaylistListResult(
                playlists: [],
                unauthorized: false,
                failed: false,
                error: nil,
                cancelled: true
            )
        }
        if result.errCode == 401 || result.errCode == 403 {
            return PlaylistListResult(
                playlists: [],
                unauthorized: true,
                failed: true,
                error: apiErrorMessage(from: result.body) ?? "YouTube authorization failed"
            )
        }
        // 404 Channel not found — soft failure for channelId lookups.
        if result.errCode == 404 {
            return PlaylistListResult(
                playlists: [],
                unauthorized: false,
                failed: true,
                error: apiErrorMessage(from: result.body) ?? "Channel not found."
            )
        }
        guard result.success,
              let data = result.body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return PlaylistListResult(
                playlists: [],
                unauthorized: false,
                failed: true,
                error: apiErrorMessage(from: result.body) ?? result.errMsg.nilIfEmpty
            )
        }
        // Genuine empty list is success with items: [] (or missing items).
        let items = json["items"] as? [[String: Any]] ?? []
        let playlists: [PlaylistPreview] = items.compactMap { item in
            guard let playlistId = item["id"] as? String, !playlistId.isEmpty,
                  let snippet = item["snippet"] as? [String: Any],
                  let title = snippet["title"] as? String, !title.isEmpty
            else { return nil }
            let thumbs = snippet["thumbnails"] as? [String: Any]
            let thumb = (thumbs?["high"] as? [String: Any])?["url"] as? String
                ?? (thumbs?["medium"] as? [String: Any])?["url"] as? String
                ?? (thumbs?["default"] as? [String: Any])?["url"] as? String
            let content = item["contentDetails"] as? [String: Any]
            let count: Int?
            if let n = content?["itemCount"] as? Int {
                count = n
            } else if let s = content?["itemCount"] as? String {
                count = Int(s)
            } else {
                count = nil
            }
            return PlaylistPreview(
                playlistId: playlistId,
                title: title,
                thumbnailUrl: thumb,
                itemCount: count
            )
        }
        return PlaylistListResult(playlists: playlists, unauthorized: false, failed: false, error: nil)
    }

    /// `search.list?forMine=true&type=playlist` — alternate listing of the user's playlists.
    private static func listPlaylistsViaSearchForMine(token: String, apiKey: String) async -> PlaylistListResult {
        var comps = URLComponents(string: "\(base)/search")
        comps?.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "forMine", value: "true"),
            URLQueryItem(name: "type", value: "playlist"),
            URLQueryItem(name: "maxResults", value: String(previewCount)),
            URLQueryItem(name: "key", value: apiKey),
        ]
        guard let url = comps?.url?.absoluteString else {
            return PlaylistListResult(playlists: [], unauthorized: false, failed: true, error: "Invalid URL")
        }
        let result = await YouTubeHTTPClient.shared.request(
            url: url,
            method: "GET",
            headers: authHeaders(token),
            body: nil
        )
        if result.isCancellation {
            return PlaylistListResult(
                playlists: [],
                unauthorized: false,
                failed: false,
                error: nil,
                cancelled: true
            )
        }
        if result.errCode == 401 || result.errCode == 403 {
            return PlaylistListResult(
                playlists: [],
                unauthorized: true,
                failed: true,
                error: apiErrorMessage(from: result.body) ?? "YouTube authorization failed"
            )
        }
        guard result.success,
              let data = result.body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]]
        else {
            return PlaylistListResult(
                playlists: [],
                unauthorized: false,
                failed: true,
                error: apiErrorMessage(from: result.body) ?? result.errMsg.nilIfEmpty
            )
        }
        let playlists: [PlaylistPreview] = items.compactMap { item in
            let idObj = item["id"] as? [String: Any]
            let playlistId = idObj?["playlistId"] as? String
            guard let playlistId, !playlistId.isEmpty else { return nil }
            if playlistId == "LL" || playlistId == "WL" || playlistId == "HL" { return nil }
            let snippet = item["snippet"] as? [String: Any]
            let title = snippet?["title"] as? String ?? playlistId
            let thumbs = snippet?["thumbnails"] as? [String: Any]
            let thumb = (thumbs?["high"] as? [String: Any])?["url"] as? String
                ?? (thumbs?["medium"] as? [String: Any])?["url"] as? String
                ?? (thumbs?["default"] as? [String: Any])?["url"] as? String
            return PlaylistPreview(
                playlistId: playlistId,
                title: title,
                thumbnailUrl: thumb,
                itemCount: nil
            )
        }
        return PlaylistListResult(playlists: playlists, unauthorized: false, failed: false, error: nil)
    }

    private static func apiErrorMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any]
        else { return nil }
        if let message = error["message"] as? String, !message.isEmpty {
            return message
        }
        if let errors = error["errors"] as? [[String: Any]],
           let reason = errors.first?["reason"] as? String {
            return reason
        }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
