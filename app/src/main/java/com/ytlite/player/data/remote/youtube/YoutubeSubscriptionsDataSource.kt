package com.ytlite.player.data.remote.youtube

import com.ytlite.player.data.model.ChannelPage
import com.ytlite.player.data.model.FeedPage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Subscription data via YouTube Data API v3 (OAuth + API key).
 *
 * @see <a href="https://developers.google.com/youtube/v3/docs/subscriptions">Subscriptions</a>
 */
class YoutubeSubscriptionsDataSource(
    private val dataApiClient: YoutubeDataApiClient = YoutubeDataApiClient.getInstance(),
) {

    var oauthTokenProvider: () -> String? = { null }

    suspend fun fetchFeed(continuation: String? = null): FeedPage? = withContext(Dispatchers.IO) {
        if (!continuation.isNullOrBlank()) return@withContext null
        fetchFeedViaDataApi()
    }

    suspend fun fetchChannels(continuation: String? = null): ChannelPage? = withContext(Dispatchers.IO) {
        val oauthToken = oauthTokenProvider() ?: return@withContext null
        if (!dataApiClient.isConfigured) return@withContext null
        dataApiClient.listSubscriptions(oauthToken, pageToken = continuation)
    }

    private fun fetchFeedViaDataApi(): FeedPage? {
        val oauthToken = oauthTokenProvider() ?: return null
        if (!dataApiClient.isConfigured) return null
        val channelPage = dataApiClient.listSubscriptions(oauthToken) ?: return null
        if (channelPage.channels.isEmpty()) return null
        return dataApiClient.buildFeedFromActivities(oauthToken, channelPage.channels)
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
