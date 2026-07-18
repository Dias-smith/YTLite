import Foundation

struct HomeChipEndpoint: Codable, Hashable, Sendable {
    let browseId: String?
    let params: String?
    let continuation: String?

    var canonicalKey: String {
        [browseId ?? "", params ?? "", continuation ?? ""].joined(separator: "|")
    }

}

struct HomeDynamicChip: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let endpoint: HomeChipEndpoint
}

struct HomeBrowsePage: Sendable {
    let videos: [VideoItem]
    let chips: [HomeDynamicChip]
    let continuation: String?
}

/// Generic home-category page (videos + next-page token).
struct HomeFeedPageResult: Sendable {
    let videos: [VideoItem]
    let continuation: String?
}

enum InnerTubeClient {
    static let browseURL = "\(YouTubeConstants.baseURL)/youtubei/v1/browse?key=\(YouTubeConstants.apiKey)"
    static let homeBrowseId = "FEwhat_to_watch"
    /// YouTube Explore → News hub channel (obsolete `FEnews` returns HTTP 400 on WEB).
    static let newsBrowseId = "UCYfdidRxbB8Qhf0Nx7ioOYw"

    static func searchVideos(query: String) async throws -> [VideoItem] {
        try await searchVideosPage(query: query).videos
    }

    /// Video search page with continuation (for home mood chips / pull-to-refresh).
    static func searchVideosPage(
        query: String,
        continuation: String? = nil
    ) async throws -> HomeFeedPageResult {
        var body: [String: Any] = ["context": clientContext()]
        if let continuation, !continuation.isEmpty {
            body["continuation"] = continuation
        } else {
            body["query"] = query
            if let params = SearchResultTab.videos.innerTubeParams {
                body["params"] = params
            }
        }
        let json = try await postJSON(
            url: YouTubeConstants.searchURL,
            body: body,
            label: continuation == nil ? "search_videos" : "search_videos_cont"
        )
        nonisolated(unsafe) let payload = json
        return await parseOffMain {
            let videos = VideoJSONParser.parseVideos(from: payload)
            let token = VideoJSONParser.parseContinuation(from: payload)
            return HomeFeedPageResult(videos: videos, continuation: token)
        }
    }

    /// Current YouTube live streams. The opaque params value is YouTube's "Live" feature filter.
    static func fetchLiveVideos() async throws -> [VideoItem] {
        try await fetchLiveVideosPage().videos
    }

    static func fetchLiveVideosPage(continuation: String? = nil) async throws -> HomeFeedPageResult {
        var body: [String: Any] = ["context": clientContext()]
        if let continuation, !continuation.isEmpty {
            body["continuation"] = continuation
        } else {
            body["query"] = "live"
            body["params"] = "EgJAAQ%3D%3D"
        }
        let json = try await postJSON(
            url: YouTubeConstants.searchURL,
            body: body,
            label: continuation == nil ? "search_live" : "search_live_cont"
        )
        nonisolated(unsafe) let payload = json
        return await parseOffMain {
            let videos = VideoJSONParser.parseVideos(from: payload).filter(\.isLive)
            let token = VideoJSONParser.parseContinuation(from: payload)
            return HomeFeedPageResult(videos: videos, continuation: token)
        }
    }

    /// YouTube News hub (channel browse) with search fallback.
    static func fetchNewsVideos() async throws -> [VideoItem] {
        try await fetchNewsVideosPage().videos
    }

    static func fetchNewsVideosPage(continuation: String? = nil) async throws -> HomeFeedPageResult {
        // Browse News hub when possible; never surface HTTP 400 from obsolete browseIds.
        do {
            var body: [String: Any] = ["context": clientContext()]
            if let continuation, !continuation.isEmpty {
                body["continuation"] = continuation
            } else {
                body["browseId"] = newsBrowseId
            }
            let json = try await postJSON(
                url: browseURL,
                body: body,
                label: continuation == nil ? "news" : "news_cont"
            )
            nonisolated(unsafe) let payload = json
            let page = await parseOffMain {
                let videos = VideoJSONParser.parseVideos(from: payload)
                let token = VideoJSONParser.parseContinuation(from: payload)
                return HomeFeedPageResult(videos: videos, continuation: token)
            }
            if !page.videos.isEmpty { return page }
        } catch {
            // Invalid browse / stale continuation → search below.
        }
        if let continuation, !continuation.isEmpty {
            // Browse continuation may be invalid after FEnews → hub migration; try search next page,
            // then cold search if that also fails.
            if let searchPage = try? await searchVideosPage(query: "news", continuation: continuation),
               !searchPage.videos.isEmpty
            {
                return searchPage
            }
        }
        return try await searchVideosPage(query: "news")
    }

    /// Tabbed search.
    /// - All: videos from YouTube Music songs; channels / playlists from www
    /// - Videos: www YouTube video search
    /// - Channels / Playlists: www
    static func search(query: String, tab: SearchResultTab) async throws -> [SearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        switch tab {
        case .videos, .channels, .playlists:
            return try await searchYouTube(query: trimmed, tab: tab)
        case .all:
            async let songsTask = searchMusicSongs(query: trimmed)
            async let webTask = searchYouTube(query: trimmed, tab: .all)
            let songs = try await songsTask
            let webHits = try await webTask
            var hits: [SearchHit] = songs.map { .video($0) }
            for hit in webHits {
                switch hit {
                case .video:
                    continue
                case .channel, .playlist:
                    hits.append(hit)
                }
            }
            return hits
        }
    }

    /// YouTube Music song search (`WEB_REMIX` + songs filter).
    static func searchMusicSongs(query: String) async throws -> [VideoItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let body: [String: Any] = [
            "context": musicClientContext(),
            "query": trimmed,
            "params": YouTubeConstants.musicSearchParamsSongs,
        ]
        let json = try await postJSON(
            url: YouTubeConstants.musicSearchURL,
            body: body,
            label: "music_search_songs",
            clientNameHeader: YouTubeConstants.musicClientNameHeader,
            clientVersion: YouTubeConstants.musicClientVersion,
            origin: YouTubeConstants.musicBaseURL
        )
        nonisolated(unsafe) let payload = json
        return await parseOffMain {
            VideoJSONParser.parseMusicSongs(from: payload)
        }
    }

    private static func searchYouTube(query: String, tab: SearchResultTab) async throws -> [SearchHit] {
        var body: [String: Any] = [
            "context": clientContext(),
            "query": query,
        ]
        if let params = tab.innerTubeParams {
            body["params"] = params
        }
        let json = try await postJSON(
            url: YouTubeConstants.searchURL,
            body: body,
            label: "search_\(tab.rawValue)"
        )
        nonisolated(unsafe) let payload = json
        return await parseOffMain {
            VideoJSONParser.parseSearchHits(from: payload, tab: tab)
        }
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

    static func fetchHomeFeedPage(continuation: String? = nil) async throws -> HomeBrowsePage {
        var body: [String: Any] = ["context": clientContext()]
        if let continuation, !continuation.isEmpty {
            body["continuation"] = continuation
        } else {
            body["browseId"] = homeBrowseId
        }
        let json = try await postJSON(
            url: browseURL,
            body: body,
            label: continuation == nil ? "home" : "home_cont"
        )
        nonisolated(unsafe) let payload = json
        async let videosTask = parseOffMain {
            VideoJSONParser.parseVideos(from: payload)
        }
        async let chipsTask = parseOffMain {
            parseHomeChips(from: payload)
        }
        async let tokenTask = parseOffMain {
            VideoJSONParser.parseContinuation(from: payload)
        }
        let videos = await videosTask
        let chips = await chipsTask
        let token = await tokenTask
        if !videos.isEmpty {
            return HomeBrowsePage(videos: videos, chips: chips, continuation: token)
        }
        if continuation != nil {
            return HomeBrowsePage(videos: [], chips: chips, continuation: nil)
        }
        let fallback = try await searchVideosPage(query: "music")
        return HomeBrowsePage(
            videos: fallback.videos,
            chips: chips,
            continuation: fallback.continuation
        )
    }

    static func fetchHomeFeed() async throws -> [VideoItem] {
        try await fetchHomeFeedPage().videos
    }

    static func fetchHomeFeed(endpoint: HomeChipEndpoint) async throws -> [VideoItem] {
        try await fetchHomeFeedPage(endpoint: endpoint).videos
    }

    static func fetchHomeFeedPage(
        endpoint: HomeChipEndpoint,
        continuation: String? = nil
    ) async throws -> HomeFeedPageResult {
        var body: [String: Any] = ["context": clientContext()]
        let token = continuation ?? endpoint.continuation
        if let token, !token.isEmpty {
            body["continuation"] = token
        } else {
            body["browseId"] = endpoint.browseId ?? homeBrowseId
            if let params = endpoint.params, !params.isEmpty {
                body["params"] = params
            }
        }
        let json = try await postJSON(
            url: browseURL,
            body: body,
            label: token == nil ? "home_chip" : "home_chip_cont"
        )
        nonisolated(unsafe) let payload = json
        return await parseOffMain {
            let videos = VideoJSONParser.parseVideos(from: payload)
            let next = VideoJSONParser.parseContinuation(from: payload)
            return HomeFeedPageResult(videos: videos, continuation: next)
        }
    }

    /// YouTube Music radio queue (`RDAMVM…`) for Related tab — same as Android `fetchMusicRadioNext`.
    static func fetchMusicRelatedVideos(videoId: String) async throws -> [VideoItem] {
        let id = videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return [] }
        let body: [String: Any] = [
            "context": musicClientContext(),
            "videoId": id,
            "playlistId": "RDAMVM\(id)",
            "racyCheckOk": true,
            "contentCheckOk": true,
        ]
        let json = try await postJSON(
            url: YouTubeConstants.musicNextURL,
            body: body,
            label: "music_radio_next",
            clientNameHeader: YouTubeConstants.musicClientNameHeader,
            clientVersion: YouTubeConstants.musicClientVersion,
            origin: YouTubeConstants.musicBaseURL
        )
        nonisolated(unsafe) let payload = json
        return await parseOffMain {
            VideoJSONParser.parseMusicRelated(from: payload, excludeVideoId: id)
        }
    }

    /// YouTube Music browse (`WEB_REMIX`).
    static func browseMusic(browseId: String, params: String? = nil) async throws -> Any {
        var body: [String: Any] = [
            "context": musicClientContext(),
            "browseId": browseId,
        ]
        if let params, !params.isEmpty {
            body["params"] = params
        }
        return try await postJSON(
            url: YouTubeConstants.musicBrowseURL,
            body: body,
            label: "music_browse",
            clientNameHeader: YouTubeConstants.musicClientNameHeader,
            clientVersion: YouTubeConstants.musicClientVersion,
            origin: YouTubeConstants.musicBaseURL
        )
    }

    /// New-release album/EP/single cards from Music.
    static func fetchMusicNewReleaseAlbums() async throws -> [MusicAlbumRelease] {
        let json = try await browseMusic(browseId: YouTubeConstants.musicBrowseIdNewReleaseAlbums)
        nonisolated(unsafe) let payload = json
        return await parseOffMain {
            VideoJSONParser.parseMusicAlbumReleases(from: payload)
        }
    }

    /// Tracks inside a Music album browse page (`MPRE…`).
    static func fetchMusicAlbumTracks(
        browseId: String,
        albumTitle: String = "",
        artistFallback: String = "",
        thumbnailFallback: URL? = nil
    ) async throws -> [VideoItem] {
        let json = try await browseMusic(browseId: browseId)
        nonisolated(unsafe) let payload = json
        return await parseOffMain {
            VideoJSONParser.parseMusicAlbumTracks(
                from: payload,
                albumTitle: albumTitle,
                artistFallback: artistFallback,
                thumbnailFallback: thumbnailFallback
            )
        }
    }

    /// Offset token for new-release paging (`nr_offset:20`).
    static let newReleaseContinuationPrefix = "nr_offset:"

    static func parseNewReleaseOffset(_ continuation: String?) -> Int {
        guard let continuation,
              continuation.hasPrefix(newReleaseContinuationPrefix),
              let value = Int(continuation.dropFirst(newReleaseContinuationPrefix.count))
        else { return 0 }
        return max(0, value)
    }

    struct HomeEntriesPage: Sendable {
        let entries: [HomeFeedEntry]
        let continuation: String?
    }

    /// Android `fetchMusicNewReleaseAlbumsFeed`: singles → track, albums → album card.
    static func fetchMusicNewReleaseFeed(
        limit: Int = 20,
        continuation: String? = nil
    ) async throws -> HomeEntriesPage {
        let offset = parseNewReleaseOffset(continuation)
        let albums = try await fetchMusicNewReleaseAlbums()
        let page = Array(albums.dropFirst(offset).prefix(max(limit, 0)))
        let maxConcurrent = 4
        let entries: [HomeFeedEntry] = await withTaskGroup(of: (Int, HomeFeedEntry?).self) { group in
            var nextIndex = 0
            var inFlight = 0
            var paired: [(Int, HomeFeedEntry)] = []

            func enqueue() {
                while inFlight < maxConcurrent && nextIndex < page.count {
                    let index = nextIndex
                    let release = page[index]
                    nextIndex += 1
                    inFlight += 1
                    group.addTask {
                        if release.isSingle {
                            let tracks = try? await fetchMusicAlbumTracks(
                                browseId: release.browseId,
                                albumTitle: release.title,
                                artistFallback: release.artistName,
                                thumbnailFallback: release.thumbnailURL
                            )
                            guard var track = tracks?.first else { return (index, nil) }
                            track = VideoItem(
                                videoId: track.videoId,
                                title: track.title,
                                channelName: release.artistName.isEmpty ? track.channelName : release.artistName,
                                thumbnailURL: release.thumbnailURL ?? track.thumbnailURL,
                                channelAvatarURL: track.channelAvatarURL,
                                durationText: track.durationText,
                                viewCountText: track.viewCountText,
                                publishedTimeText: release.releaseType.isEmpty ? "Single" : release.releaseType
                            )
                            return (index, .track(track))
                        }
                        return (index, .album(release))
                    }
                }
            }

            enqueue()
            for await (index, entry) in group {
                inFlight -= 1
                if let entry { paired.append((index, entry)) }
                enqueue()
            }
            return paired.sorted { $0.0 < $1.0 }.map(\.1)
        }
        let nextOffset = offset + page.count
        let nextToken = nextOffset < albums.count
            ? "\(newReleaseContinuationPrefix)\(nextOffset)"
            : nil
        return HomeEntriesPage(entries: entries, continuation: nextToken)
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

    /// Channel videos via public InnerTube.
    /// Prefer UC→UU uploads playlist; for Music Topic / artist channels (often album-only),
    /// fall back to browsing the channel and expanding albums/playlists.
    static func fetchChannelUploads(channelId: String) async throws -> [VideoItem] {
        let id = channelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return [] }

        var byId: [String: VideoItem] = [:]
        func absorb(_ items: [VideoItem]) {
            for item in items {
                byId[item.videoId] = item
            }
        }

        if id.hasPrefix("UC"), id.count > 2 {
            let uploadsId = "UU" + id.dropFirst(2)
            absorb(try await fetchPlaylistVideos(playlistId: String(uploadsId)))
        }

        // Music Topic / artist channels often expose albums on Home instead of a Videos tab.
        // Expand those when uploads are missing or very thin.
        if byId.count < 5 {
            let shelf = try await fetchChannelShelf(channelId: id)
            absorb(shelf.videos)
            let playlistIds = Array(shelf.playlistIds.prefix(12))
            let maxConcurrent = 3
            await withTaskGroup(of: [VideoItem].self) { group in
                var next = 0
                var inFlight = 0
                func enqueue() {
                    while inFlight < maxConcurrent && next < playlistIds.count {
                        let playlistId = playlistIds[next]
                        next += 1
                        inFlight += 1
                        group.addTask {
                            (try? await fetchPlaylistVideos(playlistId: playlistId)) ?? []
                        }
                    }
                }
                enqueue()
                for await items in group {
                    inFlight -= 1
                    absorb(items)
                    enqueue()
                }
            }
        }

        return Array(byId.values)
    }

    /// Raw channel browse: inline videos + related album/playlist ids.
    private static func fetchChannelShelf(channelId: String) async throws -> (videos: [VideoItem], playlistIds: [String]) {
        let body: [String: Any] = [
            "context": clientContext(),
            "browseId": channelId,
        ]
        let json = try await postJSON(url: browseURL, body: body, label: "channel")
        return VideoJSONParser.parseChannelShelf(from: json)
    }

    static func fetchPlaylistVideos(playlistId: String) async throws -> [VideoItem] {
        let trimmed = playlistId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let browseId = trimmed.hasPrefix("VL") ? trimmed : "VL\(trimmed)"
        let body: [String: Any] = [
            "context": clientContext(),
            "browseId": browseId,
        ]
        let json = try await postJSON(url: browseURL, body: body, label: "playlist")
        return VideoJSONParser.parseVideos(from: json)
    }

    /// Library playlists via InnerTube `FEmy_youtube` (+ Music liked playlists), using OAuth Bearer.
    static func browseLibraryPlaylists(oauthAccessToken: String) async -> [YoutubeDataApiClient.PlaylistPreview] {
        var collected: [String: YoutubeDataApiClient.PlaylistPreview] = [:]

        if let www = try? await browseAuthenticated(
            browseId: "FEmy_youtube",
            oauthAccessToken: oauthAccessToken,
            label: "library_playlists",
            music: false
        ) {
            for item in VideoJSONParser.parsePlaylists(from: www) {
                collected[item.playlistId] = YoutubeDataApiClient.PlaylistPreview(
                    playlistId: item.playlistId,
                    title: item.title,
                    thumbnailUrl: item.thumbnailURL?.absoluteString,
                    itemCount: nil
                )
            }
        }

        if collected.isEmpty,
           let music = try? await browseAuthenticated(
            browseId: "FEmusic_liked_playlists",
            oauthAccessToken: oauthAccessToken,
            label: "music_library_playlists",
            music: true
           )
        {
            for item in VideoJSONParser.parsePlaylists(from: music) {
                collected[item.playlistId] = YoutubeDataApiClient.PlaylistPreview(
                    playlistId: item.playlistId,
                    title: item.title,
                    thumbnailUrl: item.thumbnailURL?.absoluteString,
                    itemCount: nil
                )
            }
        }

        return Array(collected.values.filter {
            $0.playlistId != "LL" && $0.playlistId != "WL" && $0.playlistId != "HL"
                && !$0.playlistId.hasPrefix("UU")
        }.prefix(12))
    }

    /// Liked videos via InnerTube `VLLL` with OAuth Bearer.
    static func browseLikedVideos(oauthAccessToken: String) async -> [VideoItem] {
        guard let json = try? await browseAuthenticated(
            browseId: "VLLL",
            oauthAccessToken: oauthAccessToken,
            label: "liked_videos",
            music: false
        ) else { return [] }
        return Array(VideoJSONParser.parseVideos(from: json).prefix(50))
    }

    private static func browseAuthenticated(
        browseId: String,
        oauthAccessToken: String,
        label: String,
        music: Bool,
        depth: Int = 0
    ) async throws -> Any {
        let body: [String: Any] = [
            "context": music ? musicClientContext() : clientContext(),
            "browseId": browseId,
        ]
        let json = try await postJSON(
            url: music ? YouTubeConstants.musicBrowseURL : browseURL,
            body: body,
            label: label,
            clientNameHeader: music ? YouTubeConstants.musicClientNameHeader : YouTubeConstants.webClientNameHeader,
            clientVersion: music ? YouTubeConstants.musicClientVersion : YouTubeConstants.webClientVersion,
            origin: music ? YouTubeConstants.musicBaseURL : YouTubeConstants.baseURL,
            authorizationBearer: oauthAccessToken
        )
        guard depth < 3,
              let dict = json as? [String: Any],
              let actions = dict["onResponseReceivedActions"] as? [[String: Any]]
        else { return json }

        for action in actions {
            guard let navigate = action["navigateAction"] as? [String: Any],
                  let endpoint = navigate["endpoint"] as? [String: Any],
                  let browse = endpoint["browseEndpoint"] as? [String: Any],
                  let nextId = browse["browseId"] as? String,
                  !nextId.isEmpty
            else { continue }
            return try await browseAuthenticated(
                browseId: nextId,
                oauthAccessToken: oauthAccessToken,
                label: "\(label)_nav",
                music: music,
                depth: depth + 1
            )
        }
        return json
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

    /// Hot keywords from Data API `videos.list` mostPopular Music titles — Android `SearchRepository.fetchHotKeywords`.
    static func fetchHotKeywords(limit: Int = YouTubeConstants.hotKeywordsLimit) async -> [String] {
        await HotKeywordsCache.shared.keywords(limit: limit)
    }

    private static func fetchYoutubeMostPopularMusicTitles(limit: Int) async -> [String] {
        let key = YouTubeConstants.hotKeywordsApiKey
        guard !key.isEmpty, limit > 0 else { return [] }
        // Request extra rows so parenthesis/noise stripping still fills `limit` after dedupe.
        let maxResults = min(50, max(limit * 3, limit))
        let url =
            "https://www.googleapis.com/youtube/v3/videos?part=snippet"
            + "&chart=mostPopular"
            + "&videoCategoryId=10"
            + "&maxResults=\(maxResults)"
            + "&key=\(key)"
        let result = await YouTubeHTTPClient.shared.request(
            url: url,
            method: "GET",
            headers: ["Accept": "application/json"],
            body: nil
        )
        guard result.success,
              let data = result.body.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]]
        else {
            return []
        }
        var titles: [String] = []
        var seen = Set<String>()
        for item in items {
            guard titles.count < limit else { break }
            guard let snippet = item["snippet"] as? [String: Any],
                  let raw = snippet["title"] as? String,
                  let title = HotKeywordTitle.clean(raw)
            else { continue }
            let keyLower = title.lowercased()
            guard seen.insert(keyLower).inserted else { continue }
            titles.append(title)
        }
        return titles
    }

    private actor HotKeywordsCache {
        static let shared = HotKeywordsCache()
        private let ttl: TimeInterval = 3 * 60 * 60
        private var cached: [String] = []
        private var fetchedAt: Date?

        func keywords(limit: Int) async -> [String] {
            if let fetchedAt, Date().timeIntervalSince(fetchedAt) < ttl, !cached.isEmpty {
                return Array(cached.prefix(limit))
            }
            let derived = await InnerTubeClient.fetchYoutubeMostPopularMusicTitles(limit: limit)
            if !derived.isEmpty {
                cached = derived
                fetchedAt = Date()
            }
            return derived
        }
    }

    /// Normalizes Data API music titles into short search-chip keywords.
    private enum HotKeywordTitle {
        static func clean(_ raw: String) -> String? {
            var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            let bracketPatterns = [
                #"\([^)]*\)"#,
                #"\[[^\]]*\]"#,
                #"【[^】]*】"#,
                #"（[^）]*）"#,
            ]
            for _ in 0..<4 {
                var next = text
                for pattern in bracketPatterns {
                    next = next.replacingOccurrences(
                        of: pattern,
                        with: " ",
                        options: .regularExpression
                    )
                }
                next = collapseSpaces(next)
                if next == text { break }
                text = next
            }

            let noiseSegment =
                #"^(?i)(official(\s+(music|lyric|audio))?(\s+video)?|lyrics?(\s+video)?|audio|mv|hd|4k|8k|remaster(ed)?|visualizer|theme\s+song)$"#
            let sepPattern = #"\s*[|\-–—]\s*"#
            while let regex = try? NSRegularExpression(pattern: sepPattern),
                  let match = regex.matches(
                      in: text,
                      range: NSRange(text.startIndex..., in: text)
                  ).last,
                  let fullRange = Range(match.range, in: text)
            {
                let tail = String(text[fullRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if tail.range(of: noiseSegment, options: .regularExpression) != nil {
                    text = String(text[..<fullRange.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    break
                }
            }

            text = text.replacingOccurrences(
                of: #"[\s|\-–—:·]+$"#,
                with: "",
                options: .regularExpression
            )
            text = collapseSpaces(text)
            guard text.count >= 2 else { return nil }
            return text
        }

        private static func collapseSpaces(_ value: String) -> String {
            value
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
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

    private static func musicClientContext() -> [String: Any] {
        [
            "client": [
                "clientName": YouTubeConstants.musicClientName,
                "clientVersion": YouTubeConstants.musicClientVersion,
                "hl": YouTubeConstants.hl,
                "gl": YouTubeConstants.gl,
            ],
        ]
    }

    private static func postJSON(
        url: String,
        body: [String: Any],
        label: String,
        clientNameHeader: String = YouTubeConstants.webClientNameHeader,
        clientVersion: String = YouTubeConstants.webClientVersion,
        origin: String = YouTubeConstants.baseURL,
        authorizationBearer: String? = nil
    ) async throws -> Any {
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let bodyString = String(data: bodyData, encoding: .utf8) ?? "{}"
        var headers: [String: String] = [
            "User-Agent": YouTubeConstants.userAgent,
            "Content-Type": "application/json",
            "X-YouTube-Client-Name": clientNameHeader,
            "X-YouTube-Client-Version": clientVersion,
            "Origin": origin,
            "Referer": "\(origin)/",
        ]
        if let authorizationBearer, !authorizationBearer.isEmpty {
            headers["Authorization"] = "Bearer \(authorizationBearer)"
        }
        let result = await YouTubeHTTPClient.shared.request(
            url: url,
            method: "POST",
            headers: headers,
            body: bodyString
        )
        if result.isCancellation {
            throw CancellationError()
        }
        guard result.success, let data = result.body.data(using: .utf8) else {
            throw ExtractorBridge.ExtractorError.extractFailed(
                result.errMsg.isEmpty ? "\(label) failed" : result.errMsg
            )
        }
        // Decode off the caller's executor (often MainActor via ViewModels).
        return try await Task.detached(priority: .userInitiated) {
            try JSONSerialization.jsonObject(with: data)
        }.value
    }

    private static func parseHomeChips(from root: Any) -> [HomeDynamicChip] {
        var queue: [Any] = [root]
        var head = 0
        var visited = 0
        var result: [HomeDynamicChip] = []
        var seen = Set<String>()

        while head < queue.count, visited < 12_000 {
            let node = queue[head]
            head += 1
            visited += 1

            if let dict = node as? [String: Any] {
                let renderer = (dict["chipCloudChipRenderer"] as? [String: Any])
                    ?? (dict["feedFilterChipBarChipRenderer"] as? [String: Any])
                if let renderer,
                   renderer["isSelected"] as? Bool != true,
                   let title = homeChipText(renderer),
                   let endpoint = homeChipEndpoint(renderer),
                   !endpoint.canonicalKey.replacingOccurrences(of: "|", with: "").isEmpty,
                   seen.insert(homeChipId(title)).inserted
                {
                    result.append(
                        HomeDynamicChip(
                            id: homeChipId(title),
                            title: title,
                            endpoint: endpoint
                        )
                    )
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
        return result
    }

    private static func homeChipId(_ title: String) -> String {
        let normalized = title.lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-z0-9\\p{Han}]", with: "", options: .regularExpression)
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return "yt_\(String(hash, radix: 16))"
    }

    private static func homeChipEndpoint(_ renderer: [String: Any]) -> HomeChipEndpoint? {
        let navigation = (renderer["navigationEndpoint"] as? [String: Any])
            ?? (renderer["serviceEndpoint"] as? [String: Any])
            ?? renderer
        let browse = navigation["browseEndpoint"] as? [String: Any]
        let continuation = navigation["continuationCommand"] as? [String: Any]
        let endpoint = HomeChipEndpoint(
            browseId: (browse?["browseId"] as? String)?.nilIfEmpty,
            params: (browse?["params"] as? String)?.nilIfEmpty,
            continuation: ((continuation?["token"] as? String)
                ?? (continuation?["continuation"] as? String))?.nilIfEmpty
        )
        return endpoint.browseId != nil || endpoint.params != nil || endpoint.continuation != nil
            ? endpoint
            : nil
    }

    private static func homeChipText(_ renderer: [String: Any]) -> String? {
        for key in ["text", "chipText", "title"] {
            if let value = renderer[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            if let dict = renderer[key] as? [String: Any] {
                if let simple = dict["simpleText"] as? String {
                    let trimmed = simple.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
                if let runs = dict["runs"] as? [[String: Any]] {
                    let joined = runs.compactMap { $0["text"] as? String }.joined()
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !joined.isEmpty { return joined }
                }
            }
        }
        return nil
    }

    /// Run heavy InnerTube tree walks off the main actor.
    private static func parseOffMain<T: Sendable>(
        _ work: @Sendable @escaping () -> T
    ) async -> T {
        await Task.detached(priority: .userInitiated) {
            work()
        }.value
    }
}

enum VideoJSONParser {
    static func parseVideos(from root: Any) -> [VideoItem] {
        var ordered: [VideoItem] = []
        var indexById: [String: Int] = [:]
        walk(root, limit: 20_000) { dict in
            if isAd(dict) { return }
            guard let item = extractAnyVideo(from: dict) else { return }
            if let idx = indexById[item.videoId] {
                ordered[idx] = mergeVideo(ordered[idx], item)
            } else {
                indexById[item.videoId] = ordered.count
                ordered.append(item)
            }
        }
        return ordered
    }

    /// Next-page token from browse/search responses (align Android `FeedParser.extractContinuation`).
    static func parseContinuation(from root: Any) -> String? {
        var queue: [Any] = [root]
        var head = 0
        var visited = 0
        while head < queue.count, visited < 12_000 {
            let node = queue[head]
            head += 1
            visited += 1
            if let dict = node as? [String: Any] {
                if let renderer = dict["continuationItemRenderer"] as? [String: Any],
                   let token = continuationToken(from: renderer)
                {
                    return token
                }
                if let viewModel = dict["continuationItemViewModel"] as? [String: Any],
                   let token = continuationToken(from: viewModel)
                {
                    return token
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
        return nil
    }

    private static func continuationToken(from node: [String: Any]) -> String? {
        if let endpoint = node["continuationEndpoint"] as? [String: Any],
           let command = endpoint["continuationCommand"] as? [String: Any],
           let token = (command["token"] as? String)?.nilIfEmpty
        {
            return token
        }
        if let command = node["continuationCommand"] as? [String: Any] {
            if let token = (command["token"] as? String)?.nilIfEmpty {
                return token
            }
            if let inner = command["innertubeCommand"] as? [String: Any],
               let nested = inner["continuationCommand"] as? [String: Any],
               let token = (nested["token"] as? String)?.nilIfEmpty
            {
                return token
            }
        }
        return nil
    }

    /// YouTube Music `musicResponsiveListItemRenderer` song rows (search / shelves).
    static func parseMusicSongs(from root: Any) -> [VideoItem] {
        var ordered: [VideoItem] = []
        var seen = Set<String>()
        walk(root, limit: 20_000) { dict in
            guard let item = extractMusicSong(from: dict), seen.insert(item.videoId).inserted else { return }
            ordered.append(item)
        }
        return ordered
    }

    /// Music `/next` RDAMVM radio queue → Related tab (playlistPanelVideoRenderer).
    static func parseMusicRelated(from root: Any, excludeVideoId: String?) -> [VideoItem] {
        var ordered: [VideoItem] = []
        var seen = Set<String>()
        let seeds = musicRelatedRoots(from: root)
        for seed in seeds {
            walk(seed, limit: 8_000) { dict in
                if isAd(dict) { return }
                guard let item = extractPlaylistPanelVideo(from: dict)
                    ?? extractAnyVideo(from: dict)
                else { return }
                if item.videoId == excludeVideoId { return }
                guard seen.insert(item.videoId).inserted else { return }
                ordered.append(item)
            }
        }
        return ordered
    }

    /// Prefer music queue roots; fall back to full response (mirrors Android RelatedVideoParser).
    private static func musicRelatedRoots(from root: Any) -> [Any] {
        guard let dict = root as? [String: Any] else { return [root] }
        var roots: [Any] = []

        if let tabs = (dict["contents"] as? [String: Any])?
            .nestedDict("singleColumnMusicWatchNextResultsRenderer")?
            .nestedDict("tabbedRenderer")?
            .nestedDict("watchNextTabbedResultsRenderer")?
            .nestedArray("tabs")
        {
            for tab in tabs {
                guard let tabDict = tab as? [String: Any],
                      let contents = tabDict
                        .nestedDict("tabRenderer")?
                        .nestedDict("content")?
                        .nestedDict("musicQueueRenderer")?
                        .nestedDict("content")?
                        .nestedDict("playlistPanelRenderer")?
                        .nestedArray("contents")
                else { continue }
                roots.append(contentsOf: contents)
            }
        }

        if let panelContents = (dict["contents"] as? [String: Any])?
            .nestedDict("playlistPanelRenderer")?
            .nestedArray("contents")
        {
            roots.append(contentsOf: panelContents)
        }

        return roots.isEmpty ? [root] : roots
    }

    static func parseMusicAlbumReleases(from root: Any) -> [MusicAlbumRelease] {
        var ordered: [MusicAlbumRelease] = []
        var seen = Set<String>()
        walk(root, limit: 20_000) { dict in
            guard let album = extractMusicAlbumRelease(from: dict),
                  seen.insert(album.browseId).inserted
            else { return }
            ordered.append(album)
        }
        return ordered
    }

    static func parseMusicAlbumTracks(
        from root: Any,
        albumTitle: String,
        artistFallback: String,
        thumbnailFallback: URL?
    ) -> [VideoItem] {
        var ordered: [VideoItem] = []
        var seen = Set<String>()
        walk(root, limit: 20_000) { dict in
            guard var item = extractMusicSong(from: dict), seen.insert(item.videoId).inserted else { return }
            let artist = item.channelName.isEmpty ? artistFallback : item.channelName
            item = VideoItem(
                videoId: item.videoId,
                title: item.title,
                channelName: artist.isEmpty ? albumTitle : artist,
                thumbnailURL: item.thumbnailURL ?? thumbnailFallback,
                channelAvatarURL: item.channelAvatarURL,
                durationText: item.durationText,
                viewCountText: item.viewCountText,
                publishedTimeText: albumTitle.nilIfEmpty ?? item.publishedTimeText
            )
            ordered.append(item)
        }
        return ordered
    }

    private static func extractMusicAlbumRelease(from node: [String: Any]) -> MusicAlbumRelease? {
        guard let renderer = node["musicTwoRowItemRenderer"] as? [String: Any] else { return nil }
        guard let nav = renderer["navigationEndpoint"] as? [String: Any],
              let browse = nav["browseEndpoint"] as? [String: Any],
              let browseId = (browse["browseId"] as? String)?.nilIfEmpty,
              browseId.hasPrefix("MPRE")
        else { return nil }
        guard let title = extractText(renderer["title"])?.nilIfEmpty else { return nil }
        let subtitle = renderer["subtitle"] as? [String: Any]
        return MusicAlbumRelease(
            browseId: browseId,
            title: title,
            artistName: extractMusicAlbumArtist(from: subtitle),
            thumbnailURL: pickMusicThumbnail(from: renderer),
            releaseType: extractMusicReleaseType(from: subtitle),
            playlistId: extractMusicPlaylistId(from: renderer)
        )
    }

    private static func extractMusicAlbumArtist(from subtitle: [String: Any]?) -> String {
        guard let runs = subtitle?["runs"] as? [[String: Any]] else {
            return extractText(subtitle) ?? ""
        }
        var artists: [String] = []
        for run in runs {
            let text = ((run["text"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = text.lowercased()
            if text.isEmpty || text == "•" || lower == "album" || lower == "ep" || lower == "single" {
                continue
            }
            artists.append(text.trimmingCharacters(in: CharacterSet(charactersIn: " •")))
        }
        if artists.isEmpty { return extractText(subtitle) ?? "" }
        return artists.joined(separator: ", ")
    }

    private static func extractMusicReleaseType(from subtitle: [String: Any]?) -> String {
        guard let runs = subtitle?["runs"] as? [[String: Any]],
              let first = runs.first?["text"] as? String
        else { return "" }
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "•" { return "" }
        return trimmed
    }

    private static func extractMusicPlaylistId(from renderer: [String: Any]) -> String? {
        if let overlay = renderer["thumbnailOverlay"] as? [String: Any],
           let thumb = overlay["musicItemThumbnailOverlayRenderer"] as? [String: Any],
           let content = thumb["content"] as? [String: Any],
           let play = content["musicPlayButtonRenderer"] as? [String: Any],
           let endpoint = play["playNavigationEndpoint"] as? [String: Any],
           let watch = endpoint["watchPlaylistEndpoint"] as? [String: Any],
           let playlistId = (watch["playlistId"] as? String)?.nilIfEmpty
        {
            return playlistId
        }
        guard let menu = renderer["menu"] as? [String: Any],
              let menuRenderer = menu["menuRenderer"] as? [String: Any],
              let items = menuRenderer["items"] as? [[String: Any]]
        else { return nil }
        for item in items {
            if let nav = item["menuNavigationItemRenderer"] as? [String: Any],
               let endpoint = nav["navigationEndpoint"] as? [String: Any],
               let watch = endpoint["watchPlaylistEndpoint"] as? [String: Any],
               let playlistId = (watch["playlistId"] as? String)?.nilIfEmpty
            {
                return playlistId
            }
        }
        return nil
    }

    /// Channel home/shelves: videos inline + album/playlist lockups to expand.
    static func parseChannelShelf(from root: Any) -> (videos: [VideoItem], playlistIds: [String]) {
        var items: [String: VideoItem] = [:]
        var playlistIds: [String] = []
        var seenPlaylist = Set<String>()
        walk(root, limit: 20_000) { dict in
            if isAd(dict) { return }
            if let item = extractAnyVideo(from: dict) {
                items[item.videoId] = mergeVideo(items[item.videoId], item)
            }
            for pid in extractRelatedPlaylistIds(from: dict) where seenPlaylist.insert(pid).inserted {
                playlistIds.append(pid)
            }
        }
        return (Array(items.values), playlistIds)
    }

    /// Prefer richer fields when the same videoId is seen in multiple renderers.
    private static func mergeVideo(_ existing: VideoItem?, _ incoming: VideoItem) -> VideoItem {
        guard let existing else { return incoming }
        return VideoItem(
            videoId: existing.videoId,
            title: existing.title.count >= incoming.title.count ? existing.title : incoming.title,
            channelName: existing.channelName.isEmpty ? incoming.channelName : existing.channelName,
            thumbnailURL: existing.thumbnailURL ?? incoming.thumbnailURL,
            channelAvatarURL: existing.channelAvatarURL ?? incoming.channelAvatarURL,
            durationText: existing.durationText ?? incoming.durationText,
            viewCountText: existing.viewCountText ?? incoming.viewCountText,
            publishedTimeText: existing.publishedTimeText ?? incoming.publishedTimeText,
            isLive: existing.isLive || incoming.isLive
        )
    }

    private static func extractAnyVideo(from node: [String: Any]) -> VideoItem? {
        if let song = extractMusicSong(from: node) {
            return song
        }
        if let lockup = node["lockupViewModel"] as? [String: Any],
           let item = extractLockupVideo(from: lockup)
        {
            return item
        }
        return extractVideo(from: node)
    }

    private static func extractMusicSong(from node: [String: Any]) -> VideoItem? {
        guard let renderer = node["musicResponsiveListItemRenderer"] as? [String: Any] else { return nil }
        let videoId = ((renderer["playlistItemData"] as? [String: Any])?["videoId"] as? String)?.nilIfEmpty
            ?? musicOverlayVideoId(from: renderer)
        guard let videoId else { return nil }

        let columns = musicFlexColumnTexts(from: renderer)
        guard let title = columns.first?.nilIfEmpty else { return nil }

        var artist = ""
        var duration: String?
        var plays: String?
        for column in columns.dropFirst() {
            let lower = column.lowercased()
            if lower.contains("play") || lower.contains("view") || lower.contains("次") {
                plays = column
                continue
            }
            let parts = column
                .components(separatedBy: "•")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for part in parts {
                let pLower = part.lowercased()
                if pLower == "song" || pLower == "video" || pLower == "single" || pLower == "album" || pLower == "ep" {
                    continue
                }
                if part.contains(":"), part.count <= 8, duration == nil {
                    duration = part
                    continue
                }
                if artist.isEmpty {
                    artist = part
                }
            }
        }

        return VideoItem(
            videoId: videoId,
            title: title,
            channelName: artist,
            thumbnailURL: pickMusicThumbnail(from: renderer),
            durationText: duration,
            viewCountText: plays,
            publishedTimeText: nil
        )
    }

    private static func musicOverlayVideoId(from renderer: [String: Any]) -> String? {
        guard let overlay = renderer["overlay"] as? [String: Any],
              let thumbOverlay = overlay["musicItemThumbnailOverlayRenderer"] as? [String: Any],
              let content = thumbOverlay["content"] as? [String: Any],
              let play = content["musicPlayButtonRenderer"] as? [String: Any],
              let endpoint = play["playNavigationEndpoint"] as? [String: Any],
              let watch = endpoint["watchEndpoint"] as? [String: Any],
              let videoId = (watch["videoId"] as? String)?.nilIfEmpty
        else { return nil }
        return videoId
    }

    private static func musicFlexColumnTexts(from renderer: [String: Any]) -> [String] {
        var texts: [String] = []
        if let flex = renderer["flexColumns"] as? [[String: Any]] {
            for column in flex {
                let textNode = (column["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])?["text"]
                if let text = extractText(textNode) {
                    texts.append(text)
                }
            }
        }
        if let fixed = renderer["fixedColumns"] as? [[String: Any]] {
            for column in fixed {
                let textNode = (column["musicResponsiveListItemFixedColumnRenderer"] as? [String: Any])?["text"]
                if let text = extractText(textNode) {
                    texts.append(text)
                }
            }
        }
        return texts
    }

    private static func pickMusicThumbnail(from renderer: [String: Any]) -> URL? {
        if let thumbWrap = renderer["thumbnail"] as? [String: Any],
           let musicThumb = thumbWrap["musicThumbnailRenderer"] as? [String: Any],
           let url = pickThumbnail(musicThumb["thumbnail"] as? [String: Any])
        {
            return url
        }
        if let thumbWrap = renderer["thumbnailRenderer"] as? [String: Any],
           let musicThumb = thumbWrap["musicThumbnailRenderer"] as? [String: Any],
           let url = pickThumbnail(musicThumb["thumbnail"] as? [String: Any])
        {
            return url
        }
        return pickThumbnail(renderer["thumbnail"] as? [String: Any])
    }

    static func parseSearchHits(from root: Any, tab: SearchResultTab) -> [SearchHit] {
        var hits: [SearchHit] = []
        var seen = Set<String>()
        walk(root) { dict in
            if isAd(dict) { return }
            switch tab {
            case .all:
                if let v = extractAnyVideo(from: dict) {
                    let id = "v:\(v.videoId)"
                    if seen.insert(id).inserted { hits.append(.video(v)) }
                } else if let c = extractChannel(from: dict) {
                    let id = "c:\(c.channelId)"
                    if seen.insert(id).inserted { hits.append(.channel(c)) }
                } else if let p = extractPlaylist(from: dict) ?? extractLockupPlaylist(from: dict) {
                    let id = "p:\(p.playlistId)"
                    if seen.insert(id).inserted { hits.append(.playlist(p)) }
                }
            case .videos:
                if let v = extractAnyVideo(from: dict) {
                    let id = "v:\(v.videoId)"
                    if seen.insert(id).inserted { hits.append(.video(v)) }
                }
            case .channels:
                if let c = extractChannel(from: dict) {
                    let id = "c:\(c.channelId)"
                    if seen.insert(id).inserted { hits.append(.channel(c)) }
                }
            case .playlists:
                if let p = extractPlaylist(from: dict) ?? extractLockupPlaylist(from: dict) {
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
            if let item = extractPlaylist(from: dict) ?? extractLockupPlaylist(from: dict) {
                items[item.playlistId] = item
            }
        }
        return Array(items.values)
    }

    private static func walk(_ root: Any, limit: Int = 8_000, visit: ([String: Any]) -> Void) {
        var queue: [Any] = [root]
        var head = 0
        var visited = 0
        while head < queue.count && visited < limit {
            let node = queue[head]
            head += 1
            visited += 1
            // Periodically compact to keep memory bounded on huge trees.
            if head > 1_024 && head * 2 > queue.count {
                queue.removeFirst(head)
                head = 0
            }
            if let dict = node as? [String: Any] {
                visit(dict)
                // Prefer content branches so video lockups are reached before chrome noise.
                for key in prioritizedKeys(dict.keys) {
                    let value = dict[key]
                    if value is [String: Any] || value is [Any] {
                        queue.append(value!)
                    }
                }
            } else if let array = node as? [Any] {
                for value in array where value is [String: Any] || value is [Any] {
                    queue.append(value)
                }
            }
        }
    }

    private static let contentPriorityKeys: Set<String> = [
        "contents", "tabs", "content", "richGridRenderer", "sectionListRenderer",
        "itemSectionRenderer", "playlistVideoListRenderer", "continuationItems",
        "lockupViewModel", "videoRenderer", "gridVideoRenderer", "compactVideoRenderer",
        "playlistVideoRenderer", "playlistPanelVideoRenderer", "richItemRenderer",
        "musicQueueRenderer", "playlistPanelRenderer",
    ]

    private static func prioritizedKeys(_ keys: Dictionary<String, Any>.Keys) -> [String] {
        keys.sorted { a, b in
            let pa = contentPriorityKeys.contains(a)
            let pb = contentPriorityKeys.contains(b)
            if pa != pb { return pa && !pb }
            return a < b
        }
    }

    private static func extractRelatedPlaylistIds(from node: [String: Any]) -> [String] {
        var ids: [String] = []
        if let lockup = node["lockupViewModel"] as? [String: Any] {
            let type = lockup["contentType"] as? String ?? ""
            if type == "LOCKUP_CONTENT_TYPE_ALBUM" || type == "LOCKUP_CONTENT_TYPE_PLAYLIST",
               let contentId = (lockup["contentId"] as? String)?.nilIfEmpty
            {
                ids.append(contentId)
            }
            if let watch = nestedWatchEndpoint(in: lockup),
               let playlistId = (watch["playlistId"] as? String)?.nilIfEmpty
            {
                ids.append(playlistId)
            }
        }
        return ids
    }

    private static func nestedWatchEndpoint(in root: [String: Any]) -> [String: Any]? {
        var queue: [Any] = [root]
        var visited = 0
        while !queue.isEmpty && visited < 200 {
            let node = queue.removeFirst()
            visited += 1
            if let dict = node as? [String: Any] {
                if let watch = dict["watchEndpoint"] as? [String: Any] {
                    return watch
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
        return nil
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
        if let panel = extractPlaylistPanelVideo(from: node) {
            return panel
        }
        let renderer = (node["videoRenderer"] as? [String: Any])
            ?? (node["gridVideoRenderer"] as? [String: Any])
            ?? (node["compactVideoRenderer"] as? [String: Any])
            ?? (node["videoCardRenderer"] as? [String: Any])
            ?? (node["playlistVideoRenderer"] as? [String: Any])
        guard let renderer,
              let videoId = renderer["videoId"] as? String,
              !videoId.isEmpty
        else { return nil }
        let title = extractText(renderer["title"]) ?? videoId
        let channel = extractText(renderer["ownerText"])
            ?? extractText(renderer["shortBylineText"])
            ?? extractText(renderer["longBylineText"])
            ?? ""
        let views = extractText(renderer["shortViewCountText"])
            ?? extractText(renderer["viewCountText"])
        let published = extractText(renderer["publishedTimeText"])
        let thumb = pickThumbnail(renderer["thumbnail"] as? [String: Any])
        let avatar = pickChannelAvatar(from: renderer)
        let duration = extractText(renderer["lengthText"])
            ?? lengthFromOverlays(renderer["thumbnailOverlays"] as? [[String: Any]])
        let live = isLiveRenderer(renderer)
        return VideoItem(
            videoId: videoId,
            title: title,
            channelName: channel,
            thumbnailURL: thumb,
            channelAvatarURL: avatar,
            durationText: live ? nil : duration,
            viewCountText: views,
            publishedTimeText: published,
            isLive: live
        )
    }

    /// YouTube Music radio / queue row (`playlistPanelVideoRenderer`).
    private static func extractPlaylistPanelVideo(from node: [String: Any]) -> VideoItem? {
        guard let renderer = node["playlistPanelVideoRenderer"] as? [String: Any] else { return nil }
        let videoId = (renderer["videoId"] as? String)?.nilIfEmpty
            ?? ((renderer["navigationEndpoint"] as? [String: Any])?
                .nestedDict("watchEndpoint")?
                .nestedString("videoId"))?.nilIfEmpty
        guard let videoId else { return nil }
        guard let title = extractText(renderer["title"])?.nilIfEmpty else { return nil }
        let channel = extractText(renderer["ownerText"])
            ?? extractText(renderer["shortBylineText"])
            ?? extractFirstRunText(renderer["longBylineText"])
            ?? ""
        let views = extractText(renderer["shortViewCountText"])
            ?? extractText(renderer["viewCountText"])
            ?? viewCountFromByline(renderer["longBylineText"])
        let duration = extractText(renderer["lengthText"])
        let thumb = pickThumbnail(renderer["thumbnail"] as? [String: Any])
        return VideoItem(
            videoId: videoId,
            title: title,
            channelName: channel,
            thumbnailURL: thumb,
            durationText: duration,
            viewCountText: views
        )
    }

    private static func extractFirstRunText(_ any: Any?) -> String? {
        guard let dict = any as? [String: Any],
              let runs = dict["runs"] as? [[String: Any]],
              let text = (runs.first?["text"] as? String)?.nilIfEmpty
        else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func viewCountFromByline(_ any: Any?) -> String? {
        guard let dict = any as? [String: Any],
              let runs = dict["runs"] as? [[String: Any]]
        else { return nil }
        for run in runs {
            let text = ((run["text"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if isViewCountText(text) { return text }
        }
        return nil
    }

    private static let videoLockupTypes: Set<String> = [
        "LOCKUP_CONTENT_TYPE_VIDEO",
        "LOCKUP_CONTENT_TYPE_VIDEO_SHORT",
    ]

    private static func extractLockupVideo(from lockup: [String: Any]) -> VideoItem? {
        let contentType = lockup["contentType"] as? String ?? ""
        guard videoLockupTypes.contains(contentType),
              let videoId = (lockup["contentId"] as? String)?.nilIfEmpty
        else { return nil }
        let metadata = lockupMetadataViewModel(from: lockup)
        guard let titleDict = metadata?["title"] as? [String: Any],
              let title = (titleDict["content"] as? String)?.nilIfEmpty
        else { return nil }

        let metaParts = collectLockupMetadataTexts(metadata)
        let channel = metaParts.first(where: isChannelNameCandidate) ?? ""
        let views = metaParts.first(where: isViewCountText)
        let published = metaParts.first(where: isPublishedText)
        let overlayText = extractLockupDuration(from: lockup)
        let live = isLiveText(overlayText) || metaParts.contains(where: isWatchingText)

        return VideoItem(
            videoId: videoId,
            title: title,
            channelName: channel,
            thumbnailURL: pickLockupThumbnail(from: lockup),
            channelAvatarURL: pickLockupAvatar(from: metadata),
            durationText: live ? nil : overlayText,
            viewCountText: views,
            publishedTimeText: published,
            isLive: live
        )
    }

    private static func isLiveRenderer(_ renderer: [String: Any]) -> Bool {
        if isWatchingText(extractText(renderer["viewCountText"]))
            || isWatchingText(extractText(renderer["shortViewCountText"]))
        {
            return true
        }
        if let badges = renderer["badges"] as? [[String: Any]] {
            for badge in badges {
                guard let metadata = badge["metadataBadgeRenderer"] as? [String: Any] else { continue }
                let style = metadata["style"] as? String
                let label = metadata["label"] as? String
                if style?.localizedCaseInsensitiveContains("LIVE") == true || isLiveText(label) {
                    return true
                }
            }
        }
        if let overlays = renderer["thumbnailOverlays"] as? [[String: Any]] {
            for overlay in overlays {
                guard let status = overlay["thumbnailOverlayTimeStatusRenderer"] as? [String: Any] else {
                    continue
                }
                let style = status["style"] as? String
                if style?.localizedCaseInsensitiveContains("LIVE") == true
                    || isLiveText(extractText(status["text"]))
                {
                    return true
                }
            }
        }
        return false
    }

    private static func isLiveText(_ text: String?) -> Bool {
        guard let text else { return false }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized == "LIVE" || normalized == "LIVE NOW" || normalized == "正在直播"
    }

    private static func isWatchingText(_ text: String?) -> Bool {
        guard let text else { return false }
        let lower = text.lowercased()
        return lower.contains("watching") || lower.contains("正在观看") || lower.contains("人正在看")
    }

    private static func extractLockupPlaylist(from node: [String: Any]) -> PlaylistPreview? {
        guard let lockup = node["lockupViewModel"] as? [String: Any],
              (lockup["contentType"] as? String) == "LOCKUP_CONTENT_TYPE_PLAYLIST",
              let playlistId = (lockup["contentId"] as? String)?.nilIfEmpty
        else { return nil }
        let metadata = lockupMetadataViewModel(from: lockup)
        guard let titleDict = metadata?["title"] as? [String: Any],
              let title = (titleDict["content"] as? String)?.nilIfEmpty
        else { return nil }
        let metaParts = collectLockupMetadataTexts(metadata)
        let owner = metaParts.first(where: isChannelNameCandidate)
        let videoCount = metaParts.first { $0.localizedCaseInsensitiveContains("video") }
        let subtitle = [owner, videoCount].compactMap { $0 }.joined(separator: " · ")
        return PlaylistPreview(
            playlistId: playlistId,
            title: title,
            subtitle: subtitle,
            thumbnailURL: pickLockupThumbnail(from: lockup)
        )
    }

    private static func lockupMetadataViewModel(from lockup: [String: Any]) -> [String: Any]? {
        guard let wrapper = lockup["metadata"] as? [String: Any] else { return nil }
        return wrapper["lockupMetadataViewModel"] as? [String: Any]
    }

    private static func collectLockupMetadataTexts(_ metadata: [String: Any]?) -> [String] {
        guard let metaInner = metadata?["metadata"] as? [String: Any],
              let container = metaInner["contentMetadataViewModel"] as? [String: Any],
              let rows = container["metadataRows"] as? [[String: Any]]
        else { return [] }
        var texts: [String] = []
        for row in rows {
            guard let parts = row["metadataParts"] as? [[String: Any]] else { continue }
            for part in parts {
                if let content = (part["text"] as? [String: Any])?["content"] as? String {
                    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { texts.append(trimmed) }
                }
            }
        }
        return texts
    }

    private static func isChannelNameCandidate(_ text: String) -> Bool {
        let lower = text.lowercased()
        return !isViewCountText(text)
            && !isPublishedText(text)
            && !lower.contains("subscriber")
            && !lower.contains("video")
    }

    private static func isViewCountText(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("view") || lower.contains("watching") || lower.contains("次观看")
    }

    private static func isPublishedText(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("ago")
            || lower.contains("streamed")
            || lower.contains("premiered")
            || lower.contains("hour")
            || lower.contains("day")
            || lower.contains("week")
            || lower.contains("month")
            || lower.contains("year")
            || lower.contains("前")
    }

    private static func pickLockupThumbnail(from lockup: [String: Any]) -> URL? {
        guard let contentImage = lockup["contentImage"] as? [String: Any] else { return nil }
        if let thumbVM = contentImage["thumbnailViewModel"] as? [String: Any],
           let image = thumbVM["image"] as? [String: Any],
           let sources = image["sources"] as? [[String: Any]]
        {
            return pickSourceURL(sources)
        }
        if let collection = contentImage["collectionThumbnailViewModel"] as? [String: Any],
           let primary = collection["primaryThumbnail"] as? [String: Any],
           let thumbVM = primary["thumbnailViewModel"] as? [String: Any],
           let image = thumbVM["image"] as? [String: Any],
           let sources = image["sources"] as? [[String: Any]]
        {
            return pickSourceURL(sources)
        }
        return nil
    }

    private static func pickLockupAvatar(from metadata: [String: Any]?) -> URL? {
        pickDecoratedAvatarURL(from: metadata?["image"] as? [String: Any])
    }

    /// Supports both `decoratedAvatarViewModel` wrappers and nested `avatarViewModel.image.sources`.
    private static func pickDecoratedAvatarURL(from container: [String: Any]?) -> URL? {
        guard let container else { return nil }
        let decorated = (container["decoratedAvatarViewModel"] as? [String: Any]) ?? container
        let avatarRoot = (decorated["avatar"] as? [String: Any]) ?? decorated
        if let avatarVM = avatarRoot["avatarViewModel"] as? [String: Any],
           let avatarImage = avatarVM["image"] as? [String: Any],
           let sources = avatarImage["sources"] as? [[String: Any]],
           let url = pickSourceURL(sources)
        {
            return url
        }
        if let avatarVM = container["avatarViewModel"] as? [String: Any],
           let avatarImage = avatarVM["image"] as? [String: Any],
           let sources = avatarImage["sources"] as? [[String: Any]]
        {
            return pickSourceURL(sources)
        }
        return nil
    }

    private static func extractLockupDuration(from lockup: [String: Any]) -> String? {
        guard let contentImage = lockup["contentImage"] as? [String: Any],
              let thumbVM = contentImage["thumbnailViewModel"] as? [String: Any],
              let overlays = thumbVM["overlays"] as? [[String: Any]]
        else { return nil }
        for overlay in overlays {
            guard let bottom = overlay["thumbnailBottomOverlayViewModel"] as? [String: Any],
                  let badges = bottom["badges"] as? [[String: Any]]
            else { continue }
            for badge in badges {
                if let badgeVM = badge["thumbnailBadgeViewModel"] as? [String: Any],
                   let text = (badgeVM["text"] as? String)?.nilIfEmpty
                {
                    return text
                }
            }
        }
        return nil
    }

    private static func pickChannelAvatar(from renderer: [String: Any]) -> URL? {
        if let supported = renderer["channelThumbnailSupportedRenderers"] as? [String: Any] {
            if let link = supported["channelThumbnailWithLinkRenderer"] as? [String: Any],
               let url = pickThumbnail(link["thumbnail"] as? [String: Any])
            {
                return url
            }
            for value in supported.values {
                if let dict = value as? [String: Any],
                   let url = pickThumbnail(dict["thumbnail"] as? [String: Any])
                        ?? pickDecoratedAvatarURL(from: dict)
                {
                    return url
                }
            }
        }
        // Current WEB search: avatar.decoratedAvatarViewModel.avatar.avatarViewModel.image.sources
        if let avatar = renderer["avatar"] as? [String: Any],
           let url = pickDecoratedAvatarURL(from: avatar) ?? pickThumbnail(avatar)
        {
            return url
        }
        if let url = pickThumbnail(renderer["channelThumbnail"] as? [String: Any]) {
            return url
        }
        if let thumbs = renderer["channelThumbnail"] as? [[String: Any]] {
            return pickSourceURL(thumbs)
        }
        return nil
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
        if let s = any as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let dict = any as? [String: Any] else { return nil }
        if let simple = dict["simpleText"] as? String {
            let trimmed = simple.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let runs = dict["runs"] as? [[String: Any]] {
            let text = runs.compactMap { $0["text"] as? String }.joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        if let accessibility = dict["accessibility"] as? [String: Any],
           let data = accessibility["accessibilityData"] as? [String: Any],
           let label = data["label"] as? String
        {
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        if let content = dict["content"] as? String {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private static func pickThumbnail(_ thumb: [String: Any]?) -> URL? {
        guard let thumbs = thumb?["thumbnails"] as? [[String: Any]] else { return nil }
        return pickSourceURL(thumbs)
    }

    private static func pickSourceURL(_ sources: [[String: Any]]) -> URL? {
        let raw = sources.reversed().compactMap { $0["url"] as? String }.first
        guard var urlString = raw, !urlString.isEmpty else { return nil }
        if urlString.hasPrefix("//") {
            urlString = "https:" + urlString
        } else if urlString.hasPrefix("http://") {
            urlString = "https://" + String(urlString.dropFirst("http://".count))
        }
        return URL(string: urlString)
    }
}

private extension Dictionary where Key == String, Value == Any {
    func nestedDict(_ key: String) -> [String: Any]? {
        self[key] as? [String: Any]
    }

    func nestedArray(_ key: String) -> [Any]? {
        self[key] as? [Any]
    }

    func nestedString(_ key: String) -> String? {
        self[key] as? String
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
