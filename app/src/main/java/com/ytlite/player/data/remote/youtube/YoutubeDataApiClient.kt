package com.ytlite.player.data.remote.youtube

import com.ytlite.player.data.auth.OwnedYoutubeChannel
import com.ytlite.player.BuildConfig
import com.ytlite.player.data.local.entity.PlaylistEntity
import com.ytlite.player.data.local.entity.PlaylistSystemType
import com.ytlite.player.data.local.entity.PlaylistTrackEntity
import com.ytlite.player.data.model.ChannelPage
import com.ytlite.player.data.model.DataSource
import com.ytlite.player.data.model.FeedPage
import com.ytlite.player.data.model.PlaylistIds
import com.ytlite.player.data.model.SubscriptionChannel
import com.ytlite.player.data.model.VideoItem
import com.ytlite.player.data.network.HttpResult
import com.ytlite.player.data.network.YouTubeHttpClient
import com.ytlite.player.data.network.YoutubeDataApiConfig
import com.ytlite.player.data.youtube.YoutubeDiagnostics
import org.json.JSONObject

/**
 * Official YouTube Data API v3 client for [subscriptions] resources.
 *
 * See: https://developers.google.com/youtube/v3/docs/subscriptions
 *
 * - [listSubscriptions] maps to subscriptions.list (channel subscription list)
 * - [buildFeedFromActivities] aggregates recent uploads via activities.list per channel
 *
 * Requires OAuth access token with https://www.googleapis.com/auth/youtube.readonly
 * and a Data API key in local.properties (YOUTUBE_DATA_API_KEY).
 */
class YoutubeDataApiClient(
    private val httpClient: YouTubeHttpClient = YouTubeHttpClient.getInstance(),
) {

    val isConfigured: Boolean
        get() = BuildConfig.YOUTUBE_DATA_API_KEY.isNotBlank()

    /**
     * Public channels.list by id (API key only). Used for Library Channels avatar enrichment.
     */
    fun fetchPublicChannelAvatar(channelId: String): String? {
        if (!isConfigured || channelId.isBlank()) return null
        val url = buildString {
            append(YoutubeDataApiConfig.CHANNELS_LIST_URL)
            append("?part=snippet")
            append("&id=$channelId")
            append("&maxResults=1")
            append("&key=${BuildConfig.YOUTUBE_DATA_API_KEY}")
        }
        return runCatching {
            val result = httpClient.request(
                url = url,
                method = "GET",
                headers = emptyMap(),
                body = null,
            )
            if (!result.success || result.result.isNullOrBlank()) {
                logApiFailure("channels.list(public)", result)
                return null
            }
            val items = JSONObject(result.result).optJSONArray("items") ?: return null
            val snippet = items.optJSONObject(0)?.optJSONObject("snippet") ?: return null
            val thumbnails = snippet.optJSONObject("thumbnails") ?: return null
            thumbnails.optJSONObject("high")?.optString("url")?.takeIf { it.isNotBlank() }
                ?: thumbnails.optJSONObject("medium")?.optString("url")?.takeIf { it.isNotBlank() }
                ?: thumbnails.optJSONObject("default")?.optString("url")?.takeIf { it.isNotBlank() }
        }.onFailure { error ->
            YoutubeDiagnostics.e("DataApi", "channels.list(public) error: ${error.message}", error)
        }.getOrNull()
    }

    fun listSubscriptions(
        oauthAccessToken: String,
        pageToken: String? = null,
        maxResults: Int = 50,
    ): ChannelPage? {
        if (!isConfigured) return null
        val url = buildString {
            append(YoutubeDataApiConfig.SUBSCRIPTIONS_LIST_URL)
            append("?part=snippet,contentDetails")
            append("&mine=true")
            append("&maxResults=$maxResults")
            append("&key=${BuildConfig.YOUTUBE_DATA_API_KEY}")
            if (!pageToken.isNullOrBlank()) {
                append("&pageToken=$pageToken")
            }
        }
        return runCatching {
            val result = httpClient.request(
                url = url,
                method = "GET",
                headers = mapOf("Authorization" to "Bearer $oauthAccessToken"),
                body = null,
            )
            if (!result.success || result.result.isNullOrBlank()) {
                logApiFailure("subscriptions.list", result)
                return null
            }
            parseSubscriptionsList(JSONObject(result.result))
        }.onFailure { error ->
            YoutubeDiagnostics.e("DataApi", "subscriptions.list error: ${error.message}", error)
        }.getOrNull()
    }

    fun listOwnedChannels(
        oauthAccessToken: String,
        maxResults: Int = 50,
    ): List<OwnedYoutubeChannel>? {
        if (!isConfigured) return null
        val channels = mutableListOf<OwnedYoutubeChannel>()
        var pageToken: String? = null
        do {
            val page = fetchOwnedChannelsPage(
                oauthAccessToken = oauthAccessToken,
                pageToken = pageToken,
                maxResults = maxResults,
            ) ?: return null
            channels += page.channels
            pageToken = page.continuation
        } while (!pageToken.isNullOrBlank())
        return channels.takeIf { it.isNotEmpty() }
    }

    fun listOwnedPlaylists(
        oauthAccessToken: String,
        ownerKey: String,
        maxResults: Int = 50,
    ): List<PlaylistEntity>? {
        if (!isConfigured) {
            YoutubeDiagnostics.logPlaylistsFetchOutcome(
                step = "Playlists/DataApi",
                outcome = "skipped",
                detail = "isConfigured=false",
            )
            return null
        }
        YoutubeDiagnostics.d(
            step = "Playlists/DataApi",
            message = "listOwnedPlaylists start ownerKey=$ownerKey maxResults=$maxResults",
        )

        val channels = fetchChannelsWithRelatedPlaylists(oauthAccessToken)
        if (channels == null) {
            YoutubeDiagnostics.logPlaylistsFetchOutcome(
                step = "Playlists/DataApi",
                outcome = "failed",
                detail = "channels.list(contentDetails) returned null",
            )
            return null
        }
        if (channels.isEmpty()) {
            YoutubeDiagnostics.logPlaylistsFetchOutcome(
                step = "Playlists/DataApi",
                outcome = "fallback",
                detail = "no owned channels → trying playlists.list mine=true",
            )
            return listOwnedPlaylistsViaMine(oauthAccessToken, ownerKey, maxResults)
        }

        val results = linkedMapOf<String, PlaylistEntity>()
        for (channel in channels) {
            YoutubeDiagnostics.d(
                step = "Playlists/DataApi",
                message = "channelId=${channel.channelId} title=${channel.title} related=${channel.relatedPlaylists}",
            )
            for ((relatedKey, playlistId) in channel.relatedPlaylists) {
                if (relatedKey in SKIP_LIBRARY_RELATED_PLAYLIST_KEYS) continue
                val systemType = relatedPlaylistKeyToSystemType(relatedKey) ?: continue
                val fetched = fetchPlaylistsByIds(
                    oauthAccessToken = oauthAccessToken,
                    playlistIds = listOf(playlistId),
                    ownerKey = ownerKey,
                ) ?: continue
                fetched.forEach { playlist ->
                    results[playlist.playlistId] = playlist.copy(systemType = systemType)
                }
            }

            var pageToken: String? = null
            var pageIndex = 0
            do {
                val page = fetchPlaylistsByChannelId(
                    oauthAccessToken = oauthAccessToken,
                    channelId = channel.channelId,
                    ownerKey = ownerKey,
                    pageToken = pageToken,
                    maxResults = maxResults,
                    pageIndex = pageIndex,
                ) ?: break
                page.playlists.forEach { playlist ->
                    results.putIfAbsent(playlist.playlistId, playlist)
                }
                pageToken = page.continuation
                pageIndex++
            } while (!pageToken.isNullOrBlank())
        }

        val playlists = results.values.toList()
        YoutubeDiagnostics.logPlaylistsFetchOutcome(
            step = "Playlists/DataApi",
            outcome = "success",
            detail = "total=${playlists.size} channels=${channels.size} summaries=${playlists.map { "${it.name}(${PlaylistIds.stripYoutubePrefix(it.playlistId)})" }}",
        )
        return playlists
    }

    private fun listOwnedPlaylistsViaMine(
        oauthAccessToken: String,
        ownerKey: String,
        maxResults: Int,
    ): List<PlaylistEntity>? {
        val playlists = mutableListOf<PlaylistEntity>()
        var pageToken: String? = null
        var pageIndex = 0
        do {
            val page = fetchOwnedPlaylistsViaMinePage(
                oauthAccessToken = oauthAccessToken,
                ownerKey = ownerKey,
                pageToken = pageToken,
                maxResults = maxResults,
                pageIndex = pageIndex,
            ) ?: run {
                YoutubeDiagnostics.logPlaylistsFetchOutcome(
                    step = "Playlists/DataApi",
                    outcome = "failed",
                    detail = "fetchOwnedPlaylistsViaMinePage returned null pageIndex=$pageIndex accumulated=${playlists.size}",
                )
                return if (playlists.isEmpty()) null else playlists
            }
            playlists += page.playlists
            pageToken = page.continuation
            pageIndex++
        } while (!pageToken.isNullOrBlank())
        return playlists
    }

    private fun fetchChannelsWithRelatedPlaylists(
        oauthAccessToken: String,
        maxResults: Int = 50,
    ): List<ChannelPlaylistsContext>? {
        val channels = mutableListOf<ChannelPlaylistsContext>()
        var pageToken: String? = null
        do {
            val url = buildString {
                append(YoutubeDataApiConfig.CHANNELS_LIST_URL)
                append("?part=snippet,contentDetails")
                append("&mine=true")
                append("&maxResults=$maxResults")
                append("&key=${BuildConfig.YOUTUBE_DATA_API_KEY}")
                if (!pageToken.isNullOrBlank()) {
                    append("&pageToken=$pageToken")
                }
            }
            val result = httpClient.request(
                url = url,
                method = "GET",
                headers = mapOf("Authorization" to "Bearer $oauthAccessToken"),
                body = null,
            )
            val body = result.result.orEmpty()
            YoutubeDiagnostics.d(
                step = "Playlists/DataApi",
                message = "channels.list(contentDetails) success=${result.success} httpCode=${result.errCode} body=${body.take(800)}",
            )
            if (!result.success || body.isBlank()) {
                logApiFailure("channels.list", result)
                return null
            }
            val json = JSONObject(body)
            val items = json.optJSONArray("items") ?: break
            for (index in 0 until items.length()) {
                val item = items.optJSONObject(index) ?: continue
                val channelId = item.optString("id").takeIf { it.isNotBlank() } ?: continue
                val title = item.optJSONObject("snippet")?.optString("title").orEmpty()
                val related = item.optJSONObject("contentDetails")?.optJSONObject("relatedPlaylists")
                val relatedPlaylists = buildMap {
                    related?.keys()?.forEach { key ->
                        val playlistId = related.optString(key).takeIf { it.isNotBlank() } ?: return@forEach
                        put(key, playlistId)
                    }
                }
                channels += ChannelPlaylistsContext(
                    channelId = channelId,
                    title = title,
                    relatedPlaylists = relatedPlaylists,
                )
            }
            pageToken = json.optString("nextPageToken").takeIf { it.isNotBlank() }
        } while (!pageToken.isNullOrBlank())
        return channels
    }

    private fun fetchPlaylistsByIds(
        oauthAccessToken: String,
        playlistIds: List<String>,
        ownerKey: String,
    ): List<PlaylistEntity>? {
        if (playlistIds.isEmpty()) return emptyList()
        val url = buildString {
            append(YoutubeDataApiConfig.PLAYLISTS_LIST_URL)
            append("?part=snippet,contentDetails")
            append("&id=${playlistIds.joinToString(",")}")
            append("&key=${BuildConfig.YOUTUBE_DATA_API_KEY}")
        }
        YoutubeDiagnostics.d(
            step = "Playlists/DataApi",
            message = "request playlists.list by id=${playlistIds.joinToString(",")}",
        )
        return runCatching {
            val result = httpClient.request(
                url = url,
                method = "GET",
                headers = mapOf("Authorization" to "Bearer $oauthAccessToken"),
                body = null,
            )
            val body = result.result.orEmpty()
            YoutubeDiagnostics.logPlaylistsListResponse(
                step = "Playlists/DataApi",
                pageToken = null,
                httpCode = result.errCode,
                success = result.success && body.isNotBlank(),
                bodySnippet = body,
            )
            if (!result.success || body.isBlank()) {
                logApiFailure("playlists.list", result)
                return null
            }
            parsePlaylistsList(JSONObject(body), ownerKey, pageIndex = 0)?.playlists
        }.onFailure { error ->
            YoutubeDiagnostics.e("Playlists/DataApi", "playlists.list by id error: ${error.message}", error)
        }.getOrNull()
    }

    private fun fetchPlaylistsByChannelId(
        oauthAccessToken: String,
        channelId: String,
        ownerKey: String,
        pageToken: String?,
        maxResults: Int,
        pageIndex: Int,
    ): OwnedPlaylistsPage? {
        val url = buildString {
            append(YoutubeDataApiConfig.PLAYLISTS_LIST_URL)
            append("?part=snippet,contentDetails")
            append("&channelId=$channelId")
            append("&maxResults=$maxResults")
            append("&key=${BuildConfig.YOUTUBE_DATA_API_KEY}")
            if (!pageToken.isNullOrBlank()) {
                append("&pageToken=$pageToken")
            }
        }
        YoutubeDiagnostics.d(
            step = "Playlists/DataApi",
            message = "request playlists.list channelId=$channelId pageToken=${pageToken ?: "null"} maxResults=$maxResults",
        )
        return runCatching {
            val result = httpClient.request(
                url = url,
                method = "GET",
                headers = mapOf("Authorization" to "Bearer $oauthAccessToken"),
                body = null,
            )
            val body = result.result.orEmpty()
            YoutubeDiagnostics.logPlaylistsListResponse(
                step = "Playlists/DataApi",
                pageToken = pageToken,
                httpCode = result.errCode,
                success = result.success && body.isNotBlank(),
                bodySnippet = body,
            )
            if (!result.success || body.isBlank()) {
                logApiFailure("playlists.list", result)
                return null
            }
            parsePlaylistsList(JSONObject(body), ownerKey, pageIndex)
        }.onFailure { error ->
            YoutubeDiagnostics.e("Playlists/DataApi", "playlists.list by channelId error: ${error.message}", error)
        }.getOrNull()
    }

    fun listPlaylistItems(
        oauthAccessToken: String,
        playlistId: String,
        maxResults: Int = 50,
    ): List<PlaylistTrackEntity>? {
        if (!isConfigured) return null
        val youtubeId = PlaylistIds.stripYoutubePrefix(playlistId)
        val tracks = mutableListOf<PlaylistTrackEntity>()
        var pageToken: String? = null
        var position = 0
        do {
            val url = buildString {
                append(YoutubeDataApiConfig.PLAYLIST_ITEMS_LIST_URL)
                append("?part=snippet")
                append("&playlistId=$youtubeId")
                append("&maxResults=$maxResults")
                append("&key=${BuildConfig.YOUTUBE_DATA_API_KEY}")
                if (!pageToken.isNullOrBlank()) {
                    append("&pageToken=$pageToken")
                }
            }
            val result = httpClient.request(
                url = url,
                method = "GET",
                headers = mapOf("Authorization" to "Bearer $oauthAccessToken"),
                body = null,
            )
            if (!result.success || result.result.isNullOrBlank()) {
                logApiFailure("playlistItems.list", result)
                return null
            }
            val json = JSONObject(result.result)
            val items = json.optJSONArray("items") ?: break
            for (index in 0 until items.length()) {
                val item = items.optJSONObject(index) ?: continue
                val snippet = item.optJSONObject("snippet") ?: continue
                val videoId = snippet.optJSONObject("resourceId")
                    ?.optString("videoId")
                    ?.takeIf { it.isNotBlank() }
                    ?: continue
                val title = snippet.optString("title")
                if (title == "Private video" || title == "Deleted video") continue
                tracks += PlaylistTrackEntity(
                    playlistId = playlistId,
                    trackId = videoId,
                    position = position++,
                )
            }
            pageToken = json.optString("nextPageToken").takeIf { it.isNotBlank() }
        } while (!pageToken.isNullOrBlank())
        return tracks
    }

    private fun fetchOwnedPlaylistsViaMinePage(
        oauthAccessToken: String,
        pageToken: String? = null,
        maxResults: Int = 50,
        ownerKey: String = "",
        pageIndex: Int = 0,
    ): OwnedPlaylistsPage? {
        val url = buildString {
            append(YoutubeDataApiConfig.PLAYLISTS_LIST_URL)
            append("?part=snippet,contentDetails")
            append("&mine=true")
            append("&maxResults=$maxResults")
            append("&key=${BuildConfig.YOUTUBE_DATA_API_KEY}")
            if (!pageToken.isNullOrBlank()) {
                append("&pageToken=$pageToken")
            }
        }
        YoutubeDiagnostics.logPlaylistsListRequest(
            step = "Playlists/DataApi",
            pageToken = pageToken,
            maxResults = maxResults,
        )
        return runCatching {
            val result = httpClient.request(
                url = url,
                method = "GET",
                headers = mapOf("Authorization" to "Bearer $oauthAccessToken"),
                body = null,
            )
            val body = result.result.orEmpty()
            YoutubeDiagnostics.logPlaylistsListResponse(
                step = "Playlists/DataApi",
                pageToken = pageToken,
                httpCode = result.errCode,
                success = result.success && body.isNotBlank(),
                bodySnippet = body,
            )
            if (!result.success || body.isBlank()) {
                logApiFailure("playlists.list", result)
                return null
            }
            parsePlaylistsList(JSONObject(body), ownerKey, pageIndex)
        }.onFailure { error ->
            YoutubeDiagnostics.e("Playlists/DataApi", "playlists.list error: ${error.message}", error)
        }.getOrNull()
    }

    private fun fetchOwnedChannelsPage(
        oauthAccessToken: String,
        pageToken: String? = null,
        maxResults: Int = 50,
    ): OwnedChannelsPage? {
        val url = buildString {
            append(YoutubeDataApiConfig.CHANNELS_LIST_URL)
            append("?part=snippet,statistics")
            append("&mine=true")
            append("&maxResults=$maxResults")
            append("&key=${BuildConfig.YOUTUBE_DATA_API_KEY}")
            if (!pageToken.isNullOrBlank()) {
                append("&pageToken=$pageToken")
            }
        }
        return runCatching {
            val result = httpClient.request(
                url = url,
                method = "GET",
                headers = mapOf("Authorization" to "Bearer $oauthAccessToken"),
                body = null,
            )
            if (!result.success || result.result.isNullOrBlank()) {
                logApiFailure("channels.list", result)
                return null
            }
            parseOwnedChannelsList(JSONObject(result.result))
        }.onFailure { error ->
            YoutubeDiagnostics.e("DataApi", "channels.list error: ${error.message}", error)
        }.getOrNull()
    }

    fun listChannelVideos(
        oauthAccessToken: String,
        channelId: String,
        channelName: String,
        pageToken: String? = null,
        maxResults: Int = 25,
    ): FeedPage? {
        if (!isConfigured) return null
        listChannelVideosFromUploadsPlaylist(
            oauthAccessToken = oauthAccessToken,
            channelId = channelId,
            channelName = channelName,
            pageToken = pageToken,
            maxResults = maxResults,
        )?.let { page ->
            if (page.videos.isNotEmpty()) return page
        }
        return listChannelVideosFromSearch(
            oauthAccessToken = oauthAccessToken,
            channelId = channelId,
            channelName = channelName,
            pageToken = pageToken,
            maxResults = maxResults,
        )
    }

    private fun listChannelVideosFromUploadsPlaylist(
        oauthAccessToken: String,
        channelId: String,
        channelName: String,
        pageToken: String? = null,
        maxResults: Int = 25,
    ): FeedPage? {
        val uploadsPlaylistId = toUploadsPlaylistId(channelId) ?: return null
        val url = buildString {
            append(YoutubeDataApiConfig.PLAYLIST_ITEMS_LIST_URL)
            append("?part=snippet")
            append("&playlistId=$uploadsPlaylistId")
            append("&maxResults=$maxResults")
            append("&key=${BuildConfig.YOUTUBE_DATA_API_KEY}")
            if (!pageToken.isNullOrBlank()) {
                append("&pageToken=$pageToken")
            }
        }
        return runCatching {
            val result = httpClient.request(
                url = url,
                method = "GET",
                headers = mapOf("Authorization" to "Bearer $oauthAccessToken"),
                body = null,
            )
            if (!result.success || result.result.isNullOrBlank()) {
                logApiFailure("playlistItems.list", result)
                return null
            }
            parsePlaylistItems(
                json = JSONObject(result.result),
                channelName = channelName,
                channelId = channelId,
            )
        }.onFailure { error ->
            YoutubeDiagnostics.e("DataApi", "playlistItems.list error: ${error.message}", error)
        }.getOrNull()
    }

    private fun listChannelVideosFromSearch(
        oauthAccessToken: String,
        channelId: String,
        channelName: String,
        pageToken: String? = null,
        maxResults: Int = 25,
    ): FeedPage? {
        val url = buildString {
            append(YoutubeDataApiConfig.SEARCH_LIST_URL)
            append("?part=snippet")
            append("&channelId=$channelId")
            append("&type=video")
            append("&order=date")
            append("&maxResults=$maxResults")
            append("&key=${BuildConfig.YOUTUBE_DATA_API_KEY}")
            if (!pageToken.isNullOrBlank()) {
                append("&pageToken=$pageToken")
            }
        }
        return runCatching {
            val result = httpClient.request(
                url = url,
                method = "GET",
                headers = mapOf("Authorization" to "Bearer $oauthAccessToken"),
                body = null,
            )
            if (!result.success || result.result.isNullOrBlank()) {
                logApiFailure("search.list", result)
                return null
            }
            parseChannelSearchResults(
                json = JSONObject(result.result),
                channelName = channelName,
                channelId = channelId,
            )
        }.onFailure { error ->
            YoutubeDiagnostics.e("DataApi", "search.list error: ${error.message}", error)
        }.getOrNull()
    }

    private fun toUploadsPlaylistId(channelId: String): String? {
        if (!channelId.startsWith("UC") || channelId.length <= 2) return null
        return "UU" + channelId.substring(2)
    }

    private fun parsePlaylistItems(
        json: JSONObject,
        channelName: String,
        channelId: String,
    ): FeedPage? {
        val items = json.optJSONArray("items") ?: return null
        val videos = buildList {
            for (index in 0 until items.length()) {
                val item = items.optJSONObject(index) ?: continue
                val snippet = item.optJSONObject("snippet") ?: continue
                val videoId = snippet.optJSONObject("resourceId")
                    ?.optString("videoId")
                    ?.takeIf { it.isNotBlank() }
                    ?: continue
                val title = snippet.optString("title").takeIf { it.isNotBlank() } ?: continue
                if (title == "Private video" || title == "Deleted video") continue
                val itemChannelId = snippet.optString("channelId")
                if (itemChannelId.isNotBlank() && itemChannelId != channelId) continue
                val thumbnails = snippet.optJSONObject("thumbnails")
                val thumbnailUrl = thumbnails?.optJSONObject("high")?.optString("url")
                    ?: thumbnails?.optJSONObject("medium")?.optString("url")
                    ?: thumbnails?.optJSONObject("default")?.optString("url")
                    ?: "https://i.ytimg.com/img/no_thumbnail.jpg"
                add(
                    VideoItem(
                        videoId = videoId,
                        title = title,
                        channelName = snippet.optString("channelTitle").takeIf { it.isNotBlank() }
                            ?: channelName,
                        channelId = itemChannelId.takeIf { it.isNotBlank() } ?: channelId,
                        thumbnailUrl = thumbnailUrl,
                        durationText = null,
                        viewCountText = null,
                        publishedTimeText = snippet.optString("publishedAt").takeIf { it.isNotBlank() },
                    ),
                )
            }
        }
        return FeedPage(
            videos = videos,
            continuation = json.optString("nextPageToken").takeIf { it.isNotBlank() },
        )
    }

    fun buildFeedFromActivities(
        oauthAccessToken: String,
        channels: List<SubscriptionChannel>,
        maxChannels: Int = MAX_ACTIVITY_CHANNELS,
        maxPerChannel: Int = MAX_ACTIVITIES_PER_CHANNEL,
    ): FeedPage? {
        if (!isConfigured || channels.isEmpty()) return null

        val videos = linkedMapOf<String, VideoItem>()
        for (channel in channels.take(maxChannels)) {
            val channelVideos = fetchChannelActivities(
                oauthAccessToken = oauthAccessToken,
                channelId = channel.channelId,
                channelName = channel.title,
                maxResults = maxPerChannel,
            )
            channelVideos.forEach { video -> videos.putIfAbsent(video.videoId, video) }
        }
        if (videos.isEmpty()) return null
        YoutubeDiagnostics.d("DataApi", "activities feed aggregated videos=${videos.size}")
        return FeedPage(videos = videos.values.toList(), continuation = null)
    }

    private fun fetchChannelActivities(
        oauthAccessToken: String,
        channelId: String,
        channelName: String,
        maxResults: Int,
    ): List<VideoItem> {
        val url = buildString {
            append(YoutubeDataApiConfig.ACTIVITIES_LIST_URL)
            append("?part=snippet,contentDetails")
            append("&channelId=$channelId")
            append("&maxResults=$maxResults")
            append("&key=${BuildConfig.YOUTUBE_DATA_API_KEY}")
        }
        val result = httpClient.request(
            url = url,
            method = "GET",
            headers = mapOf("Authorization" to "Bearer $oauthAccessToken"),
            body = null,
        )
        if (!result.success || result.result.isNullOrBlank()) {
            logApiFailure("activities.list", result)
            return emptyList()
        }
        return parseActivities(JSONObject(result.result), channelName, channelId)
    }

    private fun parsePlaylistsList(
        json: JSONObject,
        ownerKey: String,
        pageIndex: Int = 0,
    ): OwnedPlaylistsPage? {
        val items = json.optJSONArray("items")
        if (items == null) {
            YoutubeDiagnostics.logPlaylistsParsed(
                step = "Playlists/DataApi",
                rawItemCount = -1,
                parsedCount = 0,
                skippedCount = 0,
                summaries = listOf("pageIndex=$pageIndex items=null jsonKeys=${json.keys().asSequence().toList()}"),
            )
            return null
        }
        var skipped = 0
        val summaries = mutableListOf<String>()
        val playlists = buildList {
            for (index in 0 until items.length()) {
                val item = items.optJSONObject(index)
                if (item == null) {
                    skipped++
                    continue
                }
                val youtubePlaylistId = item.optString("id").takeIf { it.isNotBlank() }
                if (youtubePlaylistId == null) {
                    skipped++
                    summaries += "index=$index missing_id"
                    continue
                }
                val snippet = item.optJSONObject("snippet")
                val title = snippet?.optString("title")?.takeIf { it.isNotBlank() }
                if (title == null) {
                    skipped++
                    summaries += "id=$youtubePlaylistId missing_title"
                    continue
                }
                summaries += "id=$youtubePlaylistId title=$title system=${resolvePlaylistSystemType(youtubePlaylistId)}"
                val thumbnails = snippet.optJSONObject("thumbnails")
                val coverUrl = thumbnails?.optJSONObject("high")?.optString("url")
                    ?: thumbnails?.optJSONObject("medium")?.optString("url")
                    ?: thumbnails?.optJSONObject("default")?.optString("url")
                add(
                    PlaylistEntity(
                        playlistId = PlaylistIds.youtube(youtubePlaylistId),
                        ownerKey = ownerKey,
                        name = title,
                        coverUrlOrPath = coverUrl,
                        description = snippet.optString("description").takeIf { it.isNotBlank() },
                        systemType = resolvePlaylistSystemType(youtubePlaylistId),
                        source = DataSource.YOUTUBE.dbValue,
                        isSynced = false,
                        updatedAt = System.currentTimeMillis(),
                    ),
                )
            }
        }
        YoutubeDiagnostics.logPlaylistsParsed(
            step = "Playlists/DataApi",
            rawItemCount = items.length(),
            parsedCount = playlists.size,
            skippedCount = skipped,
            summaries = summaries,
        )
        return OwnedPlaylistsPage(
            playlists = playlists,
            continuation = json.optString("nextPageToken").takeIf { it.isNotBlank() },
        )
    }

    private fun relatedPlaylistKeyToSystemType(key: String): String? = when (key) {
        "watchLater" -> PlaylistSystemType.WATCH_LATER
        "likes", "favorites" -> PlaylistSystemType.FAVORITES
        else -> null
    }

    private fun resolvePlaylistSystemType(youtubePlaylistId: String): String? = when (youtubePlaylistId) {
        "WL" -> PlaylistSystemType.WATCH_LATER
        "LL" -> PlaylistSystemType.FAVORITES
        else -> null
    }

    private data class ChannelPlaylistsContext(
        val channelId: String,
        val title: String,
        val relatedPlaylists: Map<String, String>,
    )

    private data class OwnedPlaylistsPage(
        val playlists: List<PlaylistEntity>,
        val continuation: String?,
    )

    private fun parseOwnedChannelsList(json: JSONObject): OwnedChannelsPage? {
        val items = json.optJSONArray("items") ?: return null
        val channels = buildList {
            for (index in 0 until items.length()) {
                val item = items.optJSONObject(index) ?: continue
                val channelId = item.optString("id").takeIf { it.isNotBlank() } ?: continue
                val snippet = item.optJSONObject("snippet") ?: continue
                val title = snippet.optString("title").takeIf { it.isNotBlank() } ?: continue
                val thumbnails = snippet.optJSONObject("thumbnails")
                val avatarUrl = thumbnails?.optJSONObject("default")?.optString("url")
                    ?: thumbnails?.optJSONObject("medium")?.optString("url")
                val customUrl = snippet.optString("customUrl").takeIf { it.isNotBlank() }
                val handle = customUrl?.let { url ->
                    if (url.startsWith("@")) url else "@$url"
                }
                val statistics = item.optJSONObject("statistics")
                val hiddenSubscribers = statistics?.optBoolean("hiddenSubscriberCount") == true
                val subscriberCount = statistics?.optString("subscriberCount")?.toLongOrNull()
                add(
                    OwnedYoutubeChannel(
                        channelId = channelId,
                        title = title,
                        handle = handle,
                        avatarUrl = avatarUrl,
                        subscriberCount = subscriberCount,
                        hiddenSubscriberCount = hiddenSubscribers,
                    ),
                )
            }
        }
        return OwnedChannelsPage(
            channels = channels,
            continuation = json.optString("nextPageToken").takeIf { it.isNotBlank() },
        ).takeIf { it.channels.isNotEmpty() }
    }

    private data class OwnedChannelsPage(
        val channels: List<OwnedYoutubeChannel>,
        val continuation: String?,
    )

    private fun parseSubscriptionsList(json: JSONObject): ChannelPage? {
        val items = json.optJSONArray("items") ?: return null
        val channels = buildList {
            for (index in 0 until items.length()) {
                val item = items.optJSONObject(index) ?: continue
                val snippet = item.optJSONObject("snippet") ?: continue
                val resourceId = snippet.optJSONObject("resourceId") ?: continue
                val channelId = resourceId.optString("channelId").takeIf { it.isNotBlank() } ?: continue
                val title = snippet.optString("title").takeIf { it.isNotBlank() } ?: continue
                val thumbnails = snippet.optJSONObject("thumbnails")
                val avatarUrl = thumbnails?.optJSONObject("default")?.optString("url")
                    ?: thumbnails?.optJSONObject("medium")?.optString("url")
                    ?: continue
                add(
                    SubscriptionChannel(
                        channelId = channelId,
                        title = title,
                        handle = null,
                        avatarUrl = avatarUrl,
                        subscriberCountText = null,
                        description = snippet.optString("description").takeIf { it.isNotBlank() },
                    ),
                )
            }
        }
        if (channels.isEmpty()) return null
        return ChannelPage(
            channels = channels,
            continuation = json.optString("nextPageToken").takeIf { it.isNotBlank() },
        )
    }

    private fun parseActivities(
        json: JSONObject,
        channelName: String,
        channelId: String,
    ): List<VideoItem> {
        val items = json.optJSONArray("items") ?: return emptyList()
        val videos = mutableListOf<VideoItem>()
        for (index in 0 until items.length()) {
            val item = items.optJSONObject(index) ?: continue
            val snippet = item.optJSONObject("snippet") ?: continue
            if (snippet.optString("type") != "upload") continue
            val contentDetails = item.optJSONObject("contentDetails") ?: continue
            val upload = contentDetails.optJSONObject("upload") ?: continue
            val videoId = upload.optString("videoId").takeIf { it.isNotBlank() } ?: continue
            val title = snippet.optString("title").takeIf { it.isNotBlank() } ?: continue
            val thumbnails = snippet.optJSONObject("thumbnails")
            val thumbnailUrl = thumbnails?.optJSONObject("high")?.optString("url")
                ?: thumbnails?.optJSONObject("medium")?.optString("url")
                ?: thumbnails?.optJSONObject("default")?.optString("url")
                ?: "https://i.ytimg.com/img/no_thumbnail.jpg"
            val publishedTimeText = snippet.optString("publishedAt").takeIf { it.isNotBlank() }
            videos.add(
                VideoItem(
                    videoId = videoId,
                    title = title,
                    channelName = channelName,
                    channelId = channelId,
                    thumbnailUrl = thumbnailUrl,
                    durationText = null,
                    viewCountText = null,
                    publishedTimeText = publishedTimeText,
                ),
            )
        }
        return videos
    }

    private fun parseChannelSearchResults(
        json: JSONObject,
        channelName: String,
        channelId: String,
    ): FeedPage? {
        val items = json.optJSONArray("items") ?: return null
        val videos = buildList {
            for (index in 0 until items.length()) {
                val item = items.optJSONObject(index) ?: continue
                val videoId = item.optJSONObject("id")?.optString("videoId")?.takeIf { it.isNotBlank() }
                    ?: continue
                val snippet = item.optJSONObject("snippet") ?: continue
                val itemChannelId = snippet.optString("channelId")
                if (itemChannelId.isNotBlank() && itemChannelId != channelId) continue
                val title = snippet.optString("title").takeIf { it.isNotBlank() } ?: continue
                val thumbnails = snippet.optJSONObject("thumbnails")
                val thumbnailUrl = thumbnails?.optJSONObject("high")?.optString("url")
                    ?: thumbnails?.optJSONObject("medium")?.optString("url")
                    ?: thumbnails?.optJSONObject("default")?.optString("url")
                    ?: "https://i.ytimg.com/img/no_thumbnail.jpg"
                add(
                    VideoItem(
                        videoId = videoId,
                        title = title,
                        channelName = snippet.optString("channelTitle").takeIf { it.isNotBlank() }
                            ?: channelName,
                        channelId = snippet.optString("channelId").takeIf { it.isNotBlank() }
                            ?: channelId,
                        thumbnailUrl = thumbnailUrl,
                        durationText = null,
                        viewCountText = null,
                        publishedTimeText = snippet.optString("publishedAt").takeIf { it.isNotBlank() },
                    ),
                )
            }
        }
        return FeedPage(
            videos = videos,
            continuation = json.optString("nextPageToken").takeIf { it.isNotBlank() },
        )
    }

    private fun logApiFailure(endpoint: String, result: HttpResult) {
        val bodySnippet = result.result?.take(500).orEmpty()
        YoutubeDiagnostics.w(
            "DataApi",
            "$endpoint failed code=${result.errCode} msg=${result.errMsg} body=$bodySnippet",
        )
    }

    companion object {
        private val SKIP_LIBRARY_RELATED_PLAYLIST_KEYS = setOf("uploads", "watchHistory")

        private const val MAX_ACTIVITY_CHANNELS = 12
        private const val MAX_ACTIVITIES_PER_CHANNEL = 4

        @Volatile
        private var instance: YoutubeDataApiClient? = null

        fun getInstance(): YoutubeDataApiClient =
            instance ?: synchronized(this) {
                instance ?: YoutubeDataApiClient().also { instance = it }
            }
    }
}
