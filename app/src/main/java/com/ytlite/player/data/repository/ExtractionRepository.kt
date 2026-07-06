package com.ytlite.player.data.repository

import android.content.Context
import android.util.Log
import com.ytlite.player.data.js.JsExtractorClient
import com.ytlite.player.data.js.JsExtractorEngine
import com.ytlite.player.data.js.JsResultMapper
import com.ytlite.player.data.model.ExtractionResult
import com.ytlite.player.data.model.FeedPage
import com.ytlite.player.data.model.VideoPlayback
import com.ytlite.player.data.network.InnerTubeApi
import com.ytlite.player.data.network.NetworkConfig
import com.ytlite.player.data.network.YouTubeNetworkException
import com.ytlite.player.data.parser.FeedParser
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Hybrid extraction: Kotlin InnerTube for home feed, JS extractor for playback.
 */
class ExtractionRepository(
    private val innerTubeApi: InnerTubeApi,
    private val jsClient: JsExtractorClient,
) {

    suspend fun fetchHomeFeed(
        keyword: String = NetworkConfig.HOME_SEARCH_QUERY,
    ): ExtractionResult<FeedPage> = withContext(Dispatchers.IO) {
        runFeedRequest {
            val browsePage = runCatching {
                FeedParser.parse(innerTubeApi.browseHome())
            }.getOrNull()

            if (browsePage != null && browsePage.videos.isNotEmpty()) {
                Log.d(TAG, "fetchHomeFeed: using browse (${browsePage.videos.size} videos)")
                browsePage
            } else {
                Log.d(TAG, "fetchHomeFeed: browse empty, falling back to search")
                val searchPage = FeedParser.parse(innerTubeApi.searchVideos(keyword))
                searchPage ?: throw YouTubeNetworkException("No videos in search response")
            }
        }
    }

    suspend fun fetchHomeFeedContinuation(
        continuation: String,
        keyword: String = NetworkConfig.HOME_SEARCH_QUERY,
    ): ExtractionResult<FeedPage> = withContext(Dispatchers.IO) {
        if (continuation.isBlank()) {
            return@withContext ExtractionResult.Error("Continuation token is empty")
        }
        runFeedRequest {
            val page = FeedParser.parse(innerTubeApi.searchVideos(keyword, continuation))
            page ?: throw YouTubeNetworkException("No videos in continuation response")
        }
    }

    suspend fun fetchVideoPlayback(
        videoId: String,
    ): ExtractionResult<VideoPlayback> = withContext(Dispatchers.IO) {
        if (videoId.isBlank()) {
            return@withContext ExtractionResult.Error("Video ID is empty")
        }
        try {
            val message = jsClient.extractVideo(videoId)
            val playback = JsResultMapper.toVideoPlayback(message)
            if (playback != null) {
                ExtractionResult.Success(playback)
            } else {
                ExtractionResult.Error(
                    JsResultMapper.playbackErrorMessage(message)
                        ?: "Unable to parse playable mp4 URL from JS extractor",
                )
            }
        } catch (e: Exception) {
            ExtractionResult.Error(
                message = "Failed to load video playback",
                cause = e,
            )
        }
    }

    private inline fun runFeedRequest(
        request: () -> FeedPage,
    ): ExtractionResult<FeedPage> {
        return try {
            val page = request()
            if (page.videos.isEmpty()) {
                ExtractionResult.Error("No recommended videos found. Please try again later.")
            } else {
                ExtractionResult.Success(page)
            }
        } catch (e: YouTubeNetworkException) {
            ExtractionResult.Error(
                message = "Network error while loading feed",
                cause = e,
            )
        } catch (e: Exception) {
            ExtractionResult.Error(
                message = "Network error while loading feed",
                cause = e,
            )
        }
    }

    companion object {
        private const val TAG = "ExtractionRepository"

        @Volatile
        private var appContext: Context? = null

        fun init(context: Context) {
            appContext = context.applicationContext
        }

        @Volatile
        private var instance: ExtractionRepository? = null

        fun getInstance(): ExtractionRepository {
            val context = appContext
                ?: throw IllegalStateException("ExtractionRepository is not initialized")
            return instance ?: synchronized(this) {
                instance ?: ExtractionRepository(
                    innerTubeApi = InnerTubeApi.getInstance(),
                    jsClient = JsExtractorClient(JsExtractorEngine.getInstance(context)),
                ).also { instance = it }
            }
        }
    }
}
