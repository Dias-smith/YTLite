package com.ytlite.player.data.remote.youtube

import com.ytlite.player.BuildConfig
import com.ytlite.player.data.model.ChannelPage
import com.ytlite.player.data.model.FeedPage
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

    private fun logApiFailure(endpoint: String, result: HttpResult) {
        YoutubeDataApiDiagnostics.logHttpFailure(endpoint, result)
    }

    companion object {
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
