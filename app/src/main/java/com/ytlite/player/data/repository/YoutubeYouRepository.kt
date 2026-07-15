package com.ytlite.player.data.repository

import android.content.Context
import com.ytlite.player.R
import com.ytlite.player.data.auth.AuthRepository
import com.ytlite.player.data.auth.UserSession
import com.ytlite.player.data.model.ExtractionResult
import com.ytlite.player.data.model.FeedPage
import com.ytlite.player.data.network.InnerTubeApi
import com.ytlite.player.data.network.YoutubeCookieJar
import com.ytlite.player.data.parser.BrowseParser
import com.ytlite.player.data.remote.youtube.YoutubeDataApiClient
import com.ytlite.player.data.remote.youtube.YoutubeYouInnerTubeIds
import com.ytlite.player.data.remote.youtube.YoutubeYouInnerTubeSection
import com.ytlite.player.data.remote.youtube.YoutubeYouPageSnapshot
import com.ytlite.player.data.remote.youtube.YoutubeYouPlaylistsPage
import com.ytlite.player.data.youtube.YoutubeDiagnostics
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext

class YoutubeYouRepository(
    context: Context,
    private val authRepository: AuthRepository,
    private val dataApiClient: YoutubeDataApiClient = YoutubeDataApiClient.getInstance(),
    private val innerTubeApi: InnerTubeApi = InnerTubeApi.getInstance(),
) {
    private val appContext = context.applicationContext

    private fun signInRequiredMessage(): String =
        appContext.getString(R.string.error_sign_in_google_first)

    fun youtubeReauthRequiredMessageForComparison(): String =
        appContext.getString(R.string.subscriptions_reauth_required)

    private fun youtubeReauthRequiredMessage(): String = youtubeReauthRequiredMessageForComparison()

    private fun resolveFetchFailureMessage(): String {
        if (!authRepository.isYoutubeDataApiKeyConfigured()) {
            return appContext.getString(R.string.error_youtube_api_not_configured)
        }
        if (authRepository.getGoogleProviderAccessToken() == null) {
            return youtubeReauthRequiredMessage()
        }
        return appContext.getString(R.string.error_load_subscriptions_failed)
    }

    suspend fun loadYouPage(): ExtractionResult<YoutubeYouPageSnapshot> = withContext(Dispatchers.IO) {
        // Do NOT call authRepository.initialize() here — it can demote Authenticated→Guest
        // during Supabase hydrate races and wipe a still-valid UI session.
        authRepository.hydrateGoogleAccessTokenFromStore()
        val session = authRepository.currentSession()
        if (session !is UserSession.Authenticated) {
            return@withContext ExtractionResult.Error(signInRequiredMessage())
        }

        // History / Watch later shelves are hidden in v1 UI — skip InnerTube calls
        // (they 404 without web cookies and waste network on every You-page refresh).
        try {
            var token = authRepository.ensureFreshGoogleAccessToken(forceRefresh = false)
            var page = fetchDataApiShelves(
                session = session,
                token = token,
            )
            if (page.needsYoutubeReauth ||
                (token != null && dataApiClient.isLastErrorUnauthorized())
            ) {
                YoutubeDiagnostics.w(TAG, "Data API auth failed; forcing silent token refresh")
                authRepository.invalidateGoogleAccessToken()
                token = authRepository.ensureFreshGoogleAccessToken(forceRefresh = true)
                page = fetchDataApiShelves(
                    session = session,
                    token = token,
                )
            }

            ExtractionResult.Success(
                page.copy(
                    history = emptyList(),
                    historyContinuation = null,
                    historyUnavailable = true,
                    watchLater = emptyList(),
                    watchLaterPlaylistId = null,
                    watchLaterContinuation = null,
                    watchLaterUnavailable = true,
                ),
            )
        } catch (e: Exception) {
            YoutubeDiagnostics.e(TAG, "loadYouPage failed: ${e.message}", e)
            ExtractionResult.Error(resolveFetchFailureMessage(), e)
        }
    }

    private suspend fun fetchDataApiShelves(
        session: UserSession.Authenticated,
        token: String?,
    ): YoutubeYouPageSnapshot = coroutineScope {
        dataApiClient.clearLastError()
        val preferredChannelId = session.profile.channelId
        val canUseDataApi = !token.isNullOrBlank() &&
            dataApiClient.isConfigured &&
            !authRepository.needsYoutubeDataApiReauth()

        if (!canUseDataApi) {
            YoutubeDiagnostics.w(
                TAG,
                "Data API unavailable token=${!token.isNullOrBlank()} " +
                    "configured=${dataApiClient.isConfigured} " +
                    "source=${authRepository.diagnoseGoogleAccessTokenSource()}",
            )
            return@coroutineScope emptySnapshot(
                session = session,
                needsYoutubeReauth = dataApiClient.isConfigured,
            )
        }

        val relatedDeferred = async {
            dataApiClient.fetchMineRelatedPlaylists(token!!, preferredChannelId)
        }
        val subsDeferred = async {
            dataApiClient.listSubscriptions(token!!, maxResults = PREVIEW_COUNT)
        }
        val playlistsDeferred = async {
            dataApiClient.listCustomPlaylistsPreview(token!!, maxResults = PREVIEW_COUNT)
        }

        val related = relatedDeferred.await().orEmpty()
        val likesId = related["likes"] ?: related["favorites"]
        val uploadsId = related["uploads"]

        val likesDeferred = async {
            if (likesId.isNullOrBlank()) null
            else dataApiClient.listPlaylistItemsPage(
                oauthAccessToken = token!!,
                playlistId = likesId,
                maxResults = PREVIEW_COUNT,
            )
        }
        val uploadsDeferred = async {
            if (uploadsId.isNullOrBlank()) null
            else dataApiClient.listPlaylistItemsPage(
                oauthAccessToken = token!!,
                playlistId = uploadsId,
                maxResults = PREVIEW_COUNT,
            )
        }

        val subsPage = subsDeferred.await()
        val playlistsPage = playlistsDeferred.await()
        val likesPage = likesDeferred.await()
        val uploadsPage = uploadsDeferred.await()

        val unauthorized = dataApiClient.isLastErrorUnauthorized()
        val totallyEmpty = related.isEmpty() &&
            subsPage == null &&
            playlistsPage == null &&
            likesPage == null &&
            uploadsPage == null
        // Null pages mean transport/API failure — genuine empty lists return empty objects, not null.
        val needsReauth = unauthorized ||
            (totallyEmpty && (token.isNullOrBlank() || unauthorized || dataApiClient.lastErrorCode in AUTH_HTTP_CODES))

        if (needsReauth) {
            YoutubeDiagnostics.w(
                TAG,
                "Data API shelves empty unauthorized=$unauthorized lastCode=${dataApiClient.lastErrorCode}",
            )
        }

        YoutubeYouPageSnapshot(
            subscriptions = subsPage?.channels.orEmpty(),
            subscriptionsContinuation = subsPage?.continuation,
            playlists = playlistsPage?.playlists.orEmpty(),
            playlistsContinuation = playlistsPage?.continuation,
            history = emptyList(),
            historyContinuation = null,
            historyUnavailable = true,
            watchLater = emptyList(),
            watchLaterPlaylistId = null,
            watchLaterContinuation = null,
            watchLaterUnavailable = true,
            liked = likesPage?.videos.orEmpty(),
            likedPlaylistId = likesId,
            likedContinuation = likesPage?.continuation,
            yourVideos = uploadsPage?.videos.orEmpty(),
            uploadsPlaylistId = uploadsId,
            yourVideosContinuation = uploadsPage?.continuation,
            channelId = session.profile.channelId,
            channelTitle = session.profile.displayName,
            channelHandle = session.profile.handle,
            channelAvatarUrl = session.profile.avatarUrl,
            needsYoutubeReauth = needsReauth,
        )
    }

    private fun emptySnapshot(
        session: UserSession.Authenticated,
        needsYoutubeReauth: Boolean,
    ): YoutubeYouPageSnapshot = YoutubeYouPageSnapshot(
        subscriptions = emptyList(),
        subscriptionsContinuation = null,
        playlists = emptyList(),
        playlistsContinuation = null,
        history = emptyList(),
        historyContinuation = null,
        historyUnavailable = true,
        watchLater = emptyList(),
        watchLaterPlaylistId = null,
        watchLaterContinuation = null,
        watchLaterUnavailable = true,
        liked = emptyList(),
        likedPlaylistId = null,
        likedContinuation = null,
        yourVideos = emptyList(),
        uploadsPlaylistId = null,
        yourVideosContinuation = null,
        channelId = session.profile.channelId,
        channelTitle = session.profile.displayName,
        channelHandle = session.profile.handle,
        channelAvatarUrl = session.profile.avatarUrl,
        needsYoutubeReauth = needsYoutubeReauth,
    )

    suspend fun fetchPlaylistItems(
        playlistId: String,
        pageToken: String? = null,
        maxResults: Int = 25,
    ): ExtractionResult<FeedPage> = withContext(Dispatchers.IO) {
        authRepository.hydrateGoogleAccessTokenFromStore()
        if (authRepository.currentSession() !is UserSession.Authenticated) {
            return@withContext ExtractionResult.Error(signInRequiredMessage())
        }

        when {
            isInnerTubeHistoryId(playlistId) -> {
                YoutubeCookieJar.syncFromWebView()
                val section = fetchHistoryInnerTube(continuation = pageToken)
                if (section.unavailable) {
                    ExtractionResult.Error(appContext.getString(R.string.youtube_you_history_unavailable))
                } else {
                    ExtractionResult.Success(
                        FeedPage(videos = section.videos, continuation = section.continuation),
                    )
                }
            }
            isInnerTubeWatchLaterId(playlistId) -> {
                YoutubeCookieJar.syncFromWebView()
                val section = fetchWatchLaterInnerTube(continuation = pageToken)
                if (section.unavailable) {
                    ExtractionResult.Error(appContext.getString(R.string.youtube_you_watch_later_unavailable))
                } else {
                    ExtractionResult.Success(
                        FeedPage(videos = section.videos, continuation = section.continuation),
                    )
                }
            }
            else -> {
                var token = authRepository.ensureFreshGoogleAccessToken()
                    ?: return@withContext ExtractionResult.Error(youtubeReauthRequiredMessage())
                dataApiClient.clearLastError()
                var page = dataApiClient.listPlaylistItemsPage(
                    oauthAccessToken = token,
                    playlistId = playlistId,
                    pageToken = pageToken,
                    maxResults = maxResults,
                )
                if (page == null && dataApiClient.isLastErrorUnauthorized()) {
                    authRepository.invalidateGoogleAccessToken()
                    token = authRepository.ensureFreshGoogleAccessToken(forceRefresh = true)
                        ?: return@withContext ExtractionResult.Error(youtubeReauthRequiredMessage())
                    page = dataApiClient.listPlaylistItemsPage(
                        oauthAccessToken = token,
                        playlistId = playlistId,
                        pageToken = pageToken,
                        maxResults = maxResults,
                    )
                }
                if (page == null) {
                    ExtractionResult.Error(
                        if (dataApiClient.isLastErrorUnauthorized()) {
                            youtubeReauthRequiredMessage()
                        } else {
                            appContext.getString(R.string.error_youtube_playlist_items_failed)
                        },
                    )
                } else {
                    ExtractionResult.Success(page)
                }
            }
        }
    }

    suspend fun fetchCustomPlaylists(
        pageToken: String? = null,
        maxResults: Int = 25,
    ): ExtractionResult<YoutubeYouPlaylistsPage> = withContext(Dispatchers.IO) {
        authRepository.hydrateGoogleAccessTokenFromStore()
        if (authRepository.currentSession() !is UserSession.Authenticated) {
            return@withContext ExtractionResult.Error(signInRequiredMessage())
        }
        var token = authRepository.ensureFreshGoogleAccessToken()
            ?: return@withContext ExtractionResult.Error(youtubeReauthRequiredMessage())
        dataApiClient.clearLastError()
        var page = dataApiClient.listCustomPlaylistsPreview(
            oauthAccessToken = token,
            maxResults = maxResults,
            pageToken = pageToken,
        )
        if (page == null && dataApiClient.isLastErrorUnauthorized()) {
            authRepository.invalidateGoogleAccessToken()
            token = authRepository.ensureFreshGoogleAccessToken(forceRefresh = true)
                ?: return@withContext ExtractionResult.Error(youtubeReauthRequiredMessage())
            page = dataApiClient.listCustomPlaylistsPreview(
                oauthAccessToken = token,
                maxResults = maxResults,
                pageToken = pageToken,
            )
        }
        if (page == null) {
            ExtractionResult.Error(
                if (dataApiClient.isLastErrorUnauthorized()) {
                    youtubeReauthRequiredMessage()
                } else {
                    appContext.getString(R.string.error_youtube_playlists_failed)
                },
            )
        } else {
            ExtractionResult.Success(page)
        }
    }

    private fun fetchHistoryInnerTube(continuation: String?): YoutubeYouInnerTubeSection {
        if (!YoutubeCookieJar.hasAuthCookies()) {
            YoutubeDiagnostics.w(TAG, "history unavailable: no auth cookies")
            return YoutubeYouInnerTubeSection(
                videos = emptyList(),
                continuation = null,
                unavailable = true,
            )
        }
        return runCatching {
            val response = innerTubeApi.browseHistory(continuation)
            val page = BrowseParser.parseVideoList(response)
            YoutubeYouInnerTubeSection(
                videos = page.rankedVideos,
                continuation = page.continuation,
                unavailable = false,
            )
        }.getOrElse { error ->
            YoutubeDiagnostics.e(TAG, "history InnerTube failed: ${error.message}", error)
            YoutubeYouInnerTubeSection(
                videos = emptyList(),
                continuation = null,
                unavailable = true,
            )
        }
    }

    private fun fetchWatchLaterInnerTube(continuation: String?): YoutubeYouInnerTubeSection {
        if (!YoutubeCookieJar.hasAuthCookies()) {
            YoutubeDiagnostics.w(TAG, "watch later unavailable: no auth cookies")
            return YoutubeYouInnerTubeSection(
                videos = emptyList(),
                continuation = null,
                unavailable = true,
            )
        }
        return runCatching {
            val response = innerTubeApi.browsePlaylistItems(
                youtubePlaylistId = YoutubeYouInnerTubeIds.WATCH_LATER,
                continuation = continuation,
                authenticated = true,
            )
            val page = BrowseParser.parseVideoList(response)
            YoutubeYouInnerTubeSection(
                videos = page.rankedVideos,
                continuation = page.continuation,
                unavailable = false,
            )
        }.getOrElse { error ->
            YoutubeDiagnostics.e(TAG, "watch later InnerTube failed: ${error.message}", error)
            YoutubeYouInnerTubeSection(
                videos = emptyList(),
                continuation = null,
                unavailable = true,
            )
        }
    }

    private fun isInnerTubeHistoryId(playlistId: String): Boolean =
        playlistId == YoutubeYouInnerTubeIds.HISTORY ||
            playlistId == "FEhistory"

    private fun isInnerTubeWatchLaterId(playlistId: String): Boolean =
        playlistId == YoutubeYouInnerTubeIds.WATCH_LATER ||
            playlistId == "VLWL"

    companion object {
        private const val TAG = "YoutubeYouRepo"
        private const val PREVIEW_COUNT = 12
        private val AUTH_HTTP_CODES = setOf(401, 403)

        @Volatile
        private var instance: YoutubeYouRepository? = null

        fun getInstance(context: Context): YoutubeYouRepository =
            instance ?: synchronized(this) {
                instance ?: YoutubeYouRepository(
                    context = context.applicationContext,
                    authRepository = AuthRepository.getInstance(context.applicationContext),
                ).also { instance = it }
            }
    }
}
