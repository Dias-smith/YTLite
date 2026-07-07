package com.ytlite.player.data.remote.youtube

import com.ytlite.player.data.model.ChannelPage
import com.ytlite.player.data.model.FeedPage
import com.ytlite.player.data.network.InnerTubeApi
import com.ytlite.player.data.network.YoutubeCookieJar
import com.ytlite.player.data.parser.FeedParser
import com.ytlite.player.data.youtube.YoutubeDiagnostics
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Subscription data source with layered fetch strategy aligned to YouTube Data API v3 model:
 *
 * - [subscriptions] resource = subscribed channels (not the video feed)
 * - Subscription video feed = aggregated content from subscribed channels
 *
 * @see <a href="https://developers.google.com/youtube/v3/docs/subscriptions">Subscriptions</a>
 */
class YoutubeSubscriptionsDataSource(
    private val innerTubeApi: InnerTubeApi = InnerTubeApi.getInstance(),
    private val dataApiClient: YoutubeDataApiClient = YoutubeDataApiClient.getInstance(),
) {

    var oauthTokenProvider: () -> String? = { null }

    suspend fun fetchFeed(continuation: String? = null): FeedPage? = withContext(Dispatchers.IO) {
        YoutubeDiagnostics.d("DataSource", "fetchFeed continuation=${continuation != null}")
        if (!YoutubeCookieJar.hasAuthCookies()) {
            YoutubeDiagnostics.w("DataSource", "fetchFeed aborted: hasAuthCookies=false")
            return@withContext null
        }

        if (!continuation.isNullOrBlank()) {
            return@withContext fetchFeedContinuation(continuation)
        }

        runCatching {
            fetchFeedInitial()
        }.onFailure { error ->
            YoutubeDiagnostics.e("DataSource", "fetchFeed failed: ${error.message}", error)
        }.getOrNull()
    }

    suspend fun fetchChannels(continuation: String? = null): ChannelPage? = withContext(Dispatchers.IO) {
        YoutubeDiagnostics.d("DataSource", "fetchChannels continuation=${continuation != null}")

        if (!continuation.isNullOrBlank()) {
            return@withContext fetchChannelsContinuation(continuation)
        }

        fetchChannelsViaDataApi()?.let { return@withContext it }

        if (!YoutubeCookieJar.hasAuthCookies()) {
            YoutubeDiagnostics.w("DataSource", "fetchChannels aborted: hasAuthCookies=false")
            return@withContext null
        }

        runCatching {
            fetchChannelsInnerTube(null)
        }.onFailure { error ->
            YoutubeDiagnostics.e("DataSource", "fetchChannels failed: ${error.message}", error)
        }.getOrNull()
    }

    private suspend fun fetchFeedInitial(): FeedPage? {
        // Tier 1: InnerTube FEsubscriptions + chip filter resolution
        val rawResponse = innerTubeApi.browseSubscriptions()
        val resolvedResponse = SubscriptionFeedResolver.resolve(rawResponse, innerTubeApi)
        val directPage = FeedParser.parse(resolvedResponse)
        if (directPage != null && directPage.videos.isNotEmpty()) {
            YoutubeDiagnostics.d(
                "DataSource",
                "fetchFeed tier1 innertube videos=${directPage.videos.size}",
            )
            return directPage
        }

        YoutubeDiagnostics.w(
            "DataSource",
            "fetchFeed tier1 empty: hasActions=${resolvedResponse.has("onResponseReceivedActions")} " +
                "hasContents=${resolvedResponse.has("contents")}",
        )

        // Tier 2: Data API subscriptions.list + activities.list (priority path)
        fetchFeedViaDataApi()?.let { apiFeed ->
            YoutubeDiagnostics.d(
                "DataSource",
                "fetchFeed tier2 Data API videos=${apiFeed.videos.size}",
            )
            return apiFeed
        }

        // Tier 3: InnerTube FEchannels -> per-channel browse aggregation
        val channelPage = fetchChannelsInnerTube(null)
        if (channelPage != null && channelPage.channels.isNotEmpty()) {
            SubscriptionFeedAggregator.buildFromChannelPage(channelPage, innerTubeApi)?.let { aggregated ->
                YoutubeDiagnostics.d(
                    "DataSource",
                    "fetchFeed tier3 innertube aggregator videos=${aggregated.videos.size}",
                )
                return aggregated
            }
        }

        return directPage
    }

    private fun fetchFeedViaDataApi(): FeedPage? {
        val oauthToken = oauthTokenProvider()
        if (oauthToken == null || !dataApiClient.isConfigured) {
            logDataApiSkip("fetchFeed", oauthToken)
            return null
        }
        val channelPage = dataApiClient.listSubscriptions(oauthToken) ?: return null
        YoutubeDiagnostics.d(
            "DataSource",
            "fetchFeed Data API channels=${channelPage.channels.size}",
        )
        if (channelPage.channels.isEmpty()) return null
        return dataApiClient.buildFeedFromActivities(oauthToken, channelPage.channels)
    }

    private fun fetchChannelsViaDataApi(): ChannelPage? {
        val oauthToken = oauthTokenProvider()
        if (oauthToken == null || !dataApiClient.isConfigured) {
            logDataApiSkip("fetchChannels", oauthToken)
            return null
        }
        return runCatching {
            dataApiClient.listSubscriptions(oauthToken)?.also { page ->
                YoutubeDiagnostics.d(
                    "DataSource",
                    "fetchChannels via Data API channels=${page.channels.size}",
                )
            }
        }.onFailure { error ->
            YoutubeDiagnostics.w("DataSource", "Data API channels failed: ${error.message}")
        }.getOrNull()
    }

    private fun logDataApiSkip(operation: String, oauthToken: String?) {
        val keyConfigured = dataApiClient.isConfigured
        val reason = when {
            !keyConfigured && oauthToken == null ->
                "oauthToken=null keyConfigured=false"
            !keyConfigured ->
                "keyConfigured=false"
            oauthToken == null ->
                "oauthToken=null keyConfigured=true"
            else -> return
        }
        YoutubeDiagnostics.w("DataSource", "Data API skip ($operation): $reason")
    }

    private suspend fun fetchFeedContinuation(continuation: String): FeedPage? {
        val response = innerTubeApi.browseSubscriptions(continuation)
        val page = FeedParser.parse(response)
        YoutubeDiagnostics.d(
            "DataSource",
            "fetchFeed continuation parsed videos=${page?.videos?.size ?: 0}",
        )
        return page
    }

    private suspend fun fetchChannelsContinuation(continuation: String): ChannelPage? {
        val oauthToken = oauthTokenProvider()
        if (oauthToken != null && dataApiClient.isConfigured) {
            dataApiClient.listSubscriptions(oauthToken, pageToken = continuation)?.let { return it }
        }
        return fetchChannelsInnerTube(continuation)
    }

    private suspend fun fetchChannelsInnerTube(continuation: String?): ChannelPage? {
        val response = innerTubeApi.browseSubscriptionChannels(continuation)
        YoutubeDiagnostics.d("DataSource", "fetchChannels api ok keys=${response.keys().asSequence().toList()}")
        val page = SubscriptionChannelParser.parse(response)
        YoutubeDiagnostics.d(
            "DataSource",
            "fetchChannels parsed channels=${page?.channels?.size ?: 0} continuation=${page?.continuation != null}",
        )
        return page
    }

    companion object {
        @Volatile
        private var instance: YoutubeSubscriptionsDataSource? = null

        fun getInstance(): YoutubeSubscriptionsDataSource =
            instance ?: synchronized(this) {
                instance ?: YoutubeSubscriptionsDataSource().also { instance = it }
            }
    }
}
