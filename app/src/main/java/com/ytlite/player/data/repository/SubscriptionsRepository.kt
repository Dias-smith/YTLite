package com.ytlite.player.data.repository

import android.content.Context
import com.ytlite.player.data.auth.AuthRepository
import com.ytlite.player.data.auth.UserSession
import com.ytlite.player.data.model.ChannelPage
import com.ytlite.player.data.model.ExtractionResult
import com.ytlite.player.data.model.FeedPage
import com.ytlite.player.data.network.YoutubeCookieJar
import com.ytlite.player.data.network.YouTubeNetworkException
import com.ytlite.player.data.remote.youtube.YoutubeSubscriptionsDataSource
import com.ytlite.player.data.youtube.YoutubeDiagnostics
import com.ytlite.player.data.youtube.YoutubeSessionManager
import com.ytlite.player.data.youtube.YoutubeSessionState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext

class SubscriptionsRepository(
    context: Context,
    private val authRepository: AuthRepository,
    private val youtubeSessionManager: YoutubeSessionManager,
    private val dataSource: YoutubeSubscriptionsDataSource,
) {
    val youtubeSessionState: StateFlow<YoutubeSessionState> = youtubeSessionManager.state

    fun isAuthenticated(): Boolean =
        authRepository.currentSession() is UserSession.Authenticated

    suspend fun ensureYoutubeSession(): YoutubeSessionState = withContext(Dispatchers.IO) {
        YoutubeDiagnostics.d("Repo", "ensureYoutubeSession start authenticated=${isAuthenticated()}")
        if (!isAuthenticated()) {
            YoutubeDiagnostics.w("Repo", "ensureYoutubeSession: not authenticated")
            return@withContext YoutubeSessionState.Disconnected
        }
        YoutubeCookieJar.syncFromWebView()
        YoutubeDiagnostics.logCookieJarState("ensure/pre-bootstrap")
        if (YoutubeCookieJar.hasAuthCookies()) {
            YoutubeDiagnostics.d("Repo", "ensureYoutubeSession: cookies already present, mark ready")
            youtubeSessionManager.markReadyIfCookiesPresent()
            return@withContext YoutubeSessionState.Ready
        }
        val currentState = youtubeSessionManager.state.value
        if (currentState is YoutubeSessionState.AwaitingInteractiveLogin ||
            currentState is YoutubeSessionState.Connecting
        ) {
            YoutubeDiagnostics.d("Repo", "ensureYoutubeSession: waiting for in-progress bootstrap state=$currentState")
        } else {
            YoutubeDiagnostics.d("Repo", "ensureYoutubeSession: triggering bootstrap")
        }
        youtubeSessionManager.bootstrapFromGoogleAccount()
        val state = youtubeSessionManager.state.value
        YoutubeDiagnostics.d("Repo", "ensureYoutubeSession end state=$state")
        YoutubeDiagnostics.logCookieJarState("ensure/post-bootstrap")
        state
    }

    suspend fun fetchFeed(): ExtractionResult<FeedPage> = withContext(Dispatchers.IO) {
        runSubscriptionRequest { dataSource.fetchFeed() }
    }

    suspend fun fetchFeedContinuation(continuation: String): ExtractionResult<FeedPage> =
        withContext(Dispatchers.IO) {
            if (continuation.isBlank()) {
                return@withContext ExtractionResult.Error("Continuation token is empty")
            }
            runSubscriptionRequest { dataSource.fetchFeed(continuation) }
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

    private suspend inline fun runSubscriptionRequest(
        request: () -> FeedPage?,
    ): ExtractionResult<FeedPage> {
        val session = ensureYoutubeSession()
        YoutubeDiagnostics.d("Repo", "fetchFeed session=$session")
        if (session is YoutubeSessionState.Error) {
            YoutubeDiagnostics.e("Repo", "fetchFeed blocked by session error: ${session.message}")
            return ExtractionResult.Error(session.message)
        }
        if (session is YoutubeSessionState.AwaitingInteractiveLogin ||
            session is YoutubeSessionState.Connecting
        ) {
            YoutubeDiagnostics.w("Repo", "fetchFeed blocked: awaiting interactive login")
            return ExtractionResult.Error(YOUTUBE_LOGIN_REQUIRED)
        }
        if (!YoutubeCookieJar.hasAuthCookies()) {
            YoutubeDiagnostics.e("Repo", "fetchFeed blocked: no auth cookies")
            YoutubeDiagnostics.logCookieJarState("fetchFeed/no-cookies")
            return ExtractionResult.Error(YOUTUBE_COOKIE_ERROR)
        }
        YoutubeDiagnostics.d(
            "Repo",
            "fetchFeed request cookiesForYoutube=${YoutubeCookieJar.debugCookiesForYoutubeRequest()}",
        )
        authRepository.logYoutubeDataApiReadiness("fetchFeed")
        return try {
            val page = request()
            YoutubeDiagnostics.d(
                "Repo",
                "fetchFeed response videos=${page?.videos?.size ?: 0} " +
                    "continuation=${page?.continuation != null}",
            )
            if (page == null || page.videos.isEmpty()) {
                if (authRepository.needsYoutubeDataApiReauth()) {
                    YoutubeDiagnostics.w("Repo", "fetchFeed empty: google access token missing, reauth required")
                    ExtractionResult.Error(YOUTUBE_REAUTH_REQUIRED)
                } else {
                    ExtractionResult.Success(FeedPage(videos = emptyList(), continuation = page?.continuation))
                }
            } else {
                ExtractionResult.Success(page)
            }
        } catch (e: YouTubeNetworkException) {
            YoutubeDiagnostics.e("Repo", "fetchFeed network error: ${e.message}", e)
            ExtractionResult.Error("Network error while loading subscriptions", e)
        } catch (e: Exception) {
            YoutubeDiagnostics.e("Repo", "fetchFeed error: ${e.message}", e)
            ExtractionResult.Error("Network error while loading subscriptions", e)
        }
    }

    private suspend inline fun runChannelRequest(
        request: () -> ChannelPage?,
    ): ExtractionResult<ChannelPage> {
        val session = ensureYoutubeSession()
        YoutubeDiagnostics.d("Repo", "fetchChannels session=$session")
        if (session is YoutubeSessionState.Error) {
            YoutubeDiagnostics.e("Repo", "fetchChannels blocked by session error: ${session.message}")
            return ExtractionResult.Error(session.message)
        }
        if (session is YoutubeSessionState.AwaitingInteractiveLogin ||
            session is YoutubeSessionState.Connecting
        ) {
            YoutubeDiagnostics.w("Repo", "fetchChannels blocked: awaiting interactive login")
            return ExtractionResult.Error(YOUTUBE_LOGIN_REQUIRED)
        }
        if (!YoutubeCookieJar.hasAuthCookies()) {
            YoutubeDiagnostics.e("Repo", "fetchChannels blocked: no auth cookies")
            YoutubeDiagnostics.logCookieJarState("fetchChannels/no-cookies")
            return ExtractionResult.Error(YOUTUBE_COOKIE_ERROR)
        }
        YoutubeDiagnostics.d(
            "Repo",
            "fetchChannels request cookiesForYoutube=${YoutubeCookieJar.debugCookiesForYoutubeRequest()}",
        )
        return try {
            val page = request()
            YoutubeDiagnostics.d(
                "Repo",
                "fetchChannels response channels=${page?.channels?.size ?: 0} " +
                    "continuation=${page?.continuation != null}",
            )
            if (page == null) {
                ExtractionResult.Success(ChannelPage(channels = emptyList(), continuation = null))
            } else {
                ExtractionResult.Success(page)
            }
        } catch (e: YouTubeNetworkException) {
            YoutubeDiagnostics.e("Repo", "fetchChannels network error: ${e.message}", e)
            ExtractionResult.Error("Network error while loading subscription channels", e)
        } catch (e: Exception) {
            YoutubeDiagnostics.e("Repo", "fetchChannels error: ${e.message}", e)
            ExtractionResult.Error("Network error while loading subscription channels", e)
        }
    }

    companion object {
        const val YOUTUBE_COOKIE_ERROR =
            "未获取到 YouTube 登录 Cookie，请确保设备已登录同一 Google 账号"

        const val YOUTUBE_LOGIN_REQUIRED = "请先完成 YouTube 账号连接"

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
