package com.ytlite.player.data.repository

import android.content.Context
import com.ytlite.player.data.auth.AuthRepository
import com.ytlite.player.data.auth.UserSession
import com.ytlite.player.R
import com.ytlite.player.data.model.ChannelPage
import com.ytlite.player.data.model.ExtractionResult
import com.ytlite.player.data.model.FeedPage
import com.ytlite.player.data.model.SubscriptionChannel
import com.ytlite.player.data.network.YouTubeNetworkException
import com.ytlite.player.data.remote.youtube.YoutubeSubscriptionsDataSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class SubscriptionsRepository(
    context: Context,
    private val authRepository: AuthRepository,
    private val dataSource: YoutubeSubscriptionsDataSource,
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

    suspend fun fetchChannelVideos(
        channel: SubscriptionChannel,
        continuation: String? = null,
    ): ExtractionResult<FeedPage> = withContext(Dispatchers.IO) {
        if (authRepository.currentSession() !is UserSession.Authenticated) {
            return@withContext ExtractionResult.Error(signInRequiredMessage())
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
            if (page == null || page.videos.isEmpty()) {
                ExtractionResult.Success(FeedPage(videos = emptyList(), continuation = null))
            } else {
                ExtractionResult.Success(page)
            }
        } catch (e: YouTubeNetworkException) {
            ExtractionResult.Error("Network error while loading channel videos", e)
        } catch (e: Exception) {
            ExtractionResult.Error("Network error while loading channel videos", e)
        }
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
