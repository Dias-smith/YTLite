package com.ytlite.player.data.remote.youtube

import com.ytlite.player.data.model.ChannelPage
import com.ytlite.player.data.model.FeedPage
import com.ytlite.player.data.model.SubscriptionChannel
import com.ytlite.player.data.model.VideoItem
import com.ytlite.player.data.network.InnerTubeApi
import com.ytlite.player.data.parser.FeedParser
import com.ytlite.player.data.youtube.YoutubeDiagnostics
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Builds a subscription video feed by aggregating recent uploads from subscribed channels.
 *
 * Mirrors the YouTube Data API model: subscriptions.list (channels) -> per-channel content.
 * Uses InnerTube channel browse when the unified FEsubscriptions feed cannot be parsed.
 */
object SubscriptionFeedAggregator {

    private const val MAX_CHANNELS = 12
    private const val VIDEOS_PER_CHANNEL = 4

    suspend fun buildFromChannels(
        channels: List<SubscriptionChannel>,
        innerTubeApi: InnerTubeApi,
    ): FeedPage? = withContext(Dispatchers.IO) {
        if (channels.isEmpty()) return@withContext null

        val videos = linkedMapOf<String, VideoItem>()
        for (channel in channels.take(MAX_CHANNELS)) {
            runCatching {
                val response = innerTubeApi.browseChannelVideos(channel.channelId)
                val page = FeedParser.parse(response) ?: return@runCatching
                page.videos.take(VIDEOS_PER_CHANNEL).forEach { video ->
                    val enriched = video.copy(
                        channelName = channel.title,
                        channelId = channel.channelId,
                    )
                    videos.putIfAbsent(enriched.videoId, enriched)
                }
            }.onFailure { error ->
                YoutubeDiagnostics.w(
                    "FeedAggregator",
                    "channel browse failed id=${channel.channelId}: ${error.message}",
                )
            }
        }

        if (videos.isEmpty()) {
            YoutubeDiagnostics.w("FeedAggregator", "no videos aggregated from ${channels.size} channels")
            return@withContext null
        }
        YoutubeDiagnostics.d("FeedAggregator", "aggregated videos=${videos.size} from channels")
        FeedPage(videos = videos.values.toList(), continuation = null)
    }

    suspend fun buildFromChannelPage(
        channelPage: ChannelPage,
        innerTubeApi: InnerTubeApi,
    ): FeedPage? = buildFromChannels(channelPage.channels, innerTubeApi)
}
