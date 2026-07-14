package com.ytlite.player.data.repository

import android.content.Context
import com.ytlite.player.R
import com.ytlite.player.data.auth.AuthRepository
import com.ytlite.player.data.auth.UserSession
import com.ytlite.player.data.model.ChannelPage
import com.ytlite.player.data.model.ExtractionResult
import com.ytlite.player.data.model.FeedPage
import com.ytlite.player.data.model.SubscriptionChannel
import com.ytlite.player.data.network.InnerTubeApi
import com.ytlite.player.data.network.YouTubeNetworkException
import com.ytlite.player.data.parser.BrowseParser
import com.ytlite.player.data.remote.youtube.YoutubeSubscriptionsDataSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class SubscriptionsRepository(
    context: Context,
    private val authRepository: AuthRepository,
    private val dataSource: YoutubeSubscriptionsDataSource,
    private val innerTubeApi: InnerTubeApi = InnerTubeApi.getInstance(),
) {
    private val appContext = context.applicationContext

    private fun signInRequiredMessage(): String =
        appContext.getString(R.string.error_sign_in_google_first)

    private fun youtubeReauthRequiredMessage(): String =
        appContext.getString(R.string.subscriptions_reauth_required)

    fun youtubeReauthRequiredMessageForComparison(): String = youtubeReauthRequiredMessage()
    private fun isAuthenticated(): Boolean =
        authRepository.currentSession() is UserSession.Authenticated

    suspend fun ensureAuthReady() {
        authRepository.initialize()
    }

    private fun resolveFetchFailureMessage(): String {
        if (!authRepository.isYoutubeDataApiKeyConfigured()) {
            return appContext.getString(R.string.error_youtube_api_not_configured)
        }
        if (authRepository.getGoogleProviderAccessToken() == null) {
            return youtubeReauthRequiredMessage()
        }
        return appContext.getString(R.string.error_load_subscriptions_failed)
    }

    suspend fun fetchFeed(): ExtractionResult<FeedPage> = withContext(Dispatchers.IO) {
        ensureAuthReady()
        runFeedRequest { dataSource.fetchFeed() }
    }

    suspend fun fetchFeedContinuation(continuation: String): ExtractionResult<FeedPage> =
        withContext(Dispatchers.IO) {
            ensureAuthReady()
            if (continuation.isBlank()) {
                return@withContext ExtractionResult.Error("Continuation token is empty")
            }
            runFeedRequest { dataSource.fetchFeed(continuation) }
        }

    suspend fun fetchChannels(): ExtractionResult<ChannelPage> = withContext(Dispatchers.IO) {
        ensureAuthReady()
        runChannelRequest { dataSource.fetchChannels() }
    }

    suspend fun fetchChannelsContinuation(continuation: String): ExtractionResult<ChannelPage> =
        withContext(Dispatchers.IO) {
            ensureAuthReady()
            if (continuation.isBlank()) {
                return@withContext ExtractionResult.Error("Continuation token is empty")
            }
            runChannelRequest { dataSource.fetchChannels(continuation) }
        }

    /**
     * Channel uploads for ChannelVideosScreen (Search / Subs).
     * Prefers public InnerTube uploads playlist (no Google sign-in required).
     */
    suspend fun fetchChannelVideos(
        channel: SubscriptionChannel,
        continuation: String? = null,
    ): ExtractionResult<FeedPage> = withContext(Dispatchers.IO) {
        val publicPage = runCatching {
            fetchChannelVideosViaInnerTube(channel, continuation)
        }.getOrNull()
        if (publicPage != null) {
            return@withContext ExtractionResult.Success(publicPage)
        }

        ensureAuthReady()
        if (authRepository.currentSession() !is UserSession.Authenticated) {
            return@withContext ExtractionResult.Error(
                appContext.getString(R.string.error_channel_videos_load_failed),
            )
        }
        if (authRepository.needsYoutubeDataApiReauth()) {
            return@withContext ExtractionResult.Error(youtubeReauthRequiredMessage())
        }
        return@withContext try {
            val page = dataSource.fetchChannelVideos(
                channelId = channel.channelId,
                channelName = channel.title,
                continuation = continuation,
            )
            if (page == null) {
                ExtractionResult.Error(appContext.getString(R.string.error_channel_videos_load_failed))
            } else {
                ExtractionResult.Success(page)
            }
        } catch (e: YouTubeNetworkException) {
            ExtractionResult.Error(appContext.getString(R.string.error_channel_videos_load_failed), e)
        } catch (e: Exception) {
            ExtractionResult.Error(appContext.getString(R.string.error_channel_videos_load_failed), e)
        }
    }

    private fun fetchChannelVideosViaInnerTube(
        channel: SubscriptionChannel,
        continuation: String?,
    ): FeedPage? {
        val uploadsPlaylistId = toUploadsPlaylistId(channel.channelId) ?: return null
        val response = innerTubeApi.browsePlaylistItems(uploadsPlaylistId, continuation)
        val page = BrowseParser.parseVideoList(response)
        val videos = page.rankedVideos.map { video ->
            video.copy(
                channelId = channel.channelId,
                channelName = channel.title.ifBlank { video.channelName },
            )
        }
        // Treat empty+no-continuation as hard failure so Data API can still try when signed in.
        if (videos.isEmpty() && page.continuation.isNullOrBlank() && continuation.isNullOrBlank()) {
            return null
        }
        return FeedPage(videos = videos, continuation = page.continuation)
    }

    private fun toUploadsPlaylistId(channelId: String): String? {
        if (!channelId.startsWith("UC") || channelId.length <= 2) return null
        return "UU" + channelId.substring(2)
    }

    private inline fun runFeedRequest(request: () -> FeedPage?): ExtractionResult<FeedPage> {
        if (!isAuthenticated()) {
            return ExtractionResult.Error(signInRequiredMessage())
        }
        if (authRepository.needsYoutubeDataApiReauth()) {
            return ExtractionResult.Error(youtubeReauthRequiredMessage())
        }
        return try {
            val page = request()
            when {
                page == null -> ExtractionResult.Error(resolveFetchFailureMessage())
                page.videos.isEmpty() -> ExtractionResult.Success(page)
                else -> ExtractionResult.Success(page)
            }
        } catch (e: YouTubeNetworkException) {
            ExtractionResult.Error("Network error while loading subscriptions", e)
        } catch (e: Exception) {
            ExtractionResult.Error("Network error while loading subscriptions", e)
        }
    }

    private inline fun runChannelRequest(request: () -> ChannelPage?): ExtractionResult<ChannelPage> {
        if (!isAuthenticated()) {
            return ExtractionResult.Error(signInRequiredMessage())
        }
        if (authRepository.needsYoutubeDataApiReauth()) {
            return ExtractionResult.Error(youtubeReauthRequiredMessage())
        }
        return try {
            val page = request()
            when {
                page == null -> ExtractionResult.Error(resolveFetchFailureMessage())
                else -> ExtractionResult.Success(page)
            }
        } catch (e: YouTubeNetworkException) {
            ExtractionResult.Error("Network error while loading subscription channels", e)
        } catch (e: Exception) {
            ExtractionResult.Error("Network error while loading subscription channels", e)
        }
    }

    companion object {
        @Volatile
        private var instance: SubscriptionsRepository? = null

        fun getInstance(context: Context): SubscriptionsRepository =
            instance ?: synchronized(this) {
                instance ?: SubscriptionsRepository(
                    context = context.applicationContext,
                    authRepository = AuthRepository.getInstance(context.applicationContext),
                    dataSource = YoutubeSubscriptionsDataSource.getInstance().also { dataSource ->
                        val auth = AuthRepository.getInstance(context.applicationContext)
                        dataSource.oauthTokenProvider = { auth.getGoogleProviderAccessToken() }
                    },
                ).also { instance = it }
            }
    }
}
