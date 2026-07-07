package com.ytlite.player.data.repository

import android.content.Context
import com.ytlite.player.data.auth.AuthRepository
import com.ytlite.player.data.auth.UserSession
import com.ytlite.player.data.model.ChannelPage
import com.ytlite.player.data.model.ExtractionResult
import com.ytlite.player.data.model.FeedPage
import com.ytlite.player.data.model.SubscriptionChannel
import com.ytlite.player.data.network.YouTubeNetworkException
import com.ytlite.player.data.remote.youtube.YoutubeSubscriptionsDataSource
import com.ytlite.player.data.youtube.YoutubeSessionManager
import com.ytlite.player.data.youtube.YoutubeSessionState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext

class SubscriptionsRepository(
    context: Context,
    private val authRepository: AuthRepository,
    youtubeSessionManager: YoutubeSessionManager,
    private val dataSource: YoutubeSubscriptionsDataSource,
) {
    val youtubeSessionState: StateFlow<YoutubeSessionState> = youtubeSessionManager.state

    private fun isAuthenticated(): Boolean =
        authRepository.currentSession() is UserSession.Authenticated

    suspend fun fetchFeed(): ExtractionResult<FeedPage> = withContext(Dispatchers.IO) {
        runFeedRequest { dataSource.fetchFeed() }
    }

    suspend fun fetchFeedContinuation(continuation: String): ExtractionResult<FeedPage> =
        withContext(Dispatchers.IO) {
            if (continuation.isBlank()) {
                return@withContext ExtractionResult.Error("Continuation token is empty")
            }
            runFeedRequest { dataSource.fetchFeed(continuation) }
        }

    suspend fun fetchChannels(): ExtractionResult<ChannelPage> = withContext(Dispatchers.IO) {
        runChannelRequest { dataSource.fetchChannels() }
    }

    suspend fun fetchChannelsContinuation(continuation: String): ExtractionResult<ChannelPage> =
        withContext(Dispatchers.IO) {
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
            return@withContext ExtractionResult.Error("请先登录 Google 账号")
        }
        if (authRepository.needsYoutubeDataApiReauth()) {
            return@withContext ExtractionResult.Error(YOUTUBE_REAUTH_REQUIRED)
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
            return ExtractionResult.Error("请先登录 Google 账号")
        }
        if (authRepository.needsYoutubeDataApiReauth()) {
            return ExtractionResult.Error(YOUTUBE_REAUTH_REQUIRED)
        }
        return try {
            val page = request()
            if (page == null || page.videos.isEmpty()) {
                ExtractionResult.Success(FeedPage(videos = emptyList(), continuation = null))
            } else {
                ExtractionResult.Success(page)
            }
        } catch (e: YouTubeNetworkException) {
            ExtractionResult.Error("Network error while loading subscriptions", e)
        } catch (e: Exception) {
            ExtractionResult.Error("Network error while loading subscriptions", e)
        }
    }

    private inline fun runChannelRequest(request: () -> ChannelPage?): ExtractionResult<ChannelPage> {
        if (!isAuthenticated()) {
            return ExtractionResult.Error("请先登录 Google 账号")
        }
        if (authRepository.needsYoutubeDataApiReauth()) {
            return ExtractionResult.Error(YOUTUBE_REAUTH_REQUIRED)
        }
        return try {
            val page = request()
            if (page == null) {
                ExtractionResult.Success(ChannelPage(channels = emptyList(), continuation = null))
            } else {
                ExtractionResult.Success(page)
            }
        } catch (e: YouTubeNetworkException) {
            ExtractionResult.Error("Network error while loading subscription channels", e)
        } catch (e: Exception) {
            ExtractionResult.Error("Network error while loading subscription channels", e)
        }
    }

    companion object {
        const val YOUTUBE_REAUTH_REQUIRED =
            "需要重新登录以授权 YouTube 数据访问。请退出账号后重新使用 Google 登录，并同意 YouTube 只读权限。"

        @Volatile
        private var instance: SubscriptionsRepository? = null

        fun getInstance(context: Context): SubscriptionsRepository =
            instance ?: synchronized(this) {
                instance ?: SubscriptionsRepository(
                    context = context.applicationContext,
                    authRepository = AuthRepository.getInstance(context.applicationContext),
                    youtubeSessionManager = YoutubeSessionManager.getInstance(context.applicationContext),
                    dataSource = YoutubeSubscriptionsDataSource.getInstance().also { dataSource ->
                        val auth = AuthRepository.getInstance(context.applicationContext)
                        dataSource.oauthTokenProvider = { auth.getGoogleProviderAccessToken() }
                    },
                ).also { instance = it }
            }
    }
}
