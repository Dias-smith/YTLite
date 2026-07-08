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
import com.ytlite.player.data.parser.RelatedVideoParser
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

/**
 * Hybrid extraction: Kotlin InnerTube for home feed, JS extractor for playback.
 */
class ExtractionRepository(
    private val innerTubeApi: InnerTubeApi,
    private val jsClient: JsExtractorClient,
) {

    suspend fun fetchHomeFeed(
        searchQuery: String? = null,
    ): ExtractionResult<FeedPage> = withContext(Dispatchers.IO) {
        runFeedRequest {
            if (searchQuery == null) {
                val browsePage = runCatching {
                    FeedParser.parse(innerTubeApi.browseHome())
                }.getOrNull()

                if (browsePage != null && browsePage.videos.isNotEmpty()) {
                    Log.d(TAG, "fetchHomeFeed: using browse (${browsePage.videos.size} videos)")
                    browsePage
                } else {
                    Log.d(TAG, "fetchHomeFeed: browse empty, falling back to search")
                    val searchPage = FeedParser.parse(innerTubeApi.searchVideos(NetworkConfig.HOME_SEARCH_QUERY))
                    searchPage ?: throw YouTubeNetworkException("No videos in search response")
                }
            } else {
                Log.d(TAG, "fetchHomeFeed: search query=$searchQuery")
                val searchPage = FeedParser.parse(innerTubeApi.searchVideos(searchQuery))
                searchPage ?: throw YouTubeNetworkException("No videos in search response")
            }
        }
    }

    suspend fun fetchHomeFeedContinuation(
        continuation: String,
        searchQuery: String? = NetworkConfig.HOME_SEARCH_QUERY,
    ): ExtractionResult<FeedPage> = withContext(Dispatchers.IO) {
        if (continuation.isBlank()) {
            return@withContext ExtractionResult.Error("Continuation token is empty")
        }
        runFeedRequest {
            val page = if (searchQuery != null) {
                FeedParser.parse(innerTubeApi.searchVideos(searchQuery, continuation))
            } else {
                FeedParser.parse(innerTubeApi.searchVideos(NetworkConfig.HOME_SEARCH_QUERY, continuation))
            }
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

    suspend fun fetchVideoPlaybackRaw(videoId: String): JSONObject? = withContext(Dispatchers.IO) {
        if (videoId.isBlank()) return@withContext null
        runCatching { jsClient.extractVideo(videoId) }.getOrNull()
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

    suspend fun fetchRelatedVideos(
        videoId: String,
        extractMessage: JSONObject? = null,
    ): ExtractionResult<List<com.ytlite.player.data.model.VideoItem>> = withContext(Dispatchers.IO) {
        if (videoId.isBlank()) {
            return@withContext ExtractionResult.Error("Video ID is empty")
        }
        try {
            extractMessage?.let { message ->
                val fromJs = RelatedVideoParser.parseFromJsExtract(message, excludeVideoId = videoId)
                Log.d(TAG, "fetchRelatedVideos jsPath count=${fromJs.size} videoId=$videoId")
                if (fromJs.isNotEmpty()) {
                    return@withContext ExtractionResult.Success(fromJs)
                }
            }
            val response = innerTubeApi.fetchWatchNext(videoId)
            val lockupCount = RelatedVideoParser.countLockupViewModels(response)
            Log.d(TAG, "fetchRelatedVideos innertube lockupViewModels=$lockupCount videoId=$videoId")
            val related = RelatedVideoParser.parse(response, excludeVideoId = videoId)
            Log.d(TAG, "fetchRelatedVideos mapped=${related.size} videoId=$videoId")
            if (related.isEmpty()) {
                ExtractionResult.Error("No related videos found")
            } else {
                ExtractionResult.Success(related)
            }
        } catch (e: Exception) {
            Log.e(TAG, "fetchRelatedVideos failed videoId=$videoId", e)
            ExtractionResult.Error(
                message = "Failed to load related videos",
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
