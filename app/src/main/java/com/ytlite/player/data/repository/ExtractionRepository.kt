package com.ytlite.player.data.repository

import android.content.Context
import android.util.Log
import com.ytlite.player.data.js.JsExtractorClient
import com.ytlite.player.data.js.JsExtractorEngine
import com.ytlite.player.data.js.JsResultMapper
import com.ytlite.player.data.model.ExtractionResult
import com.ytlite.player.data.model.FeedPage
import com.ytlite.player.data.model.HomeFeedItem
import com.ytlite.player.data.model.HomeFeedPage
import com.ytlite.player.data.model.VideoPlayback
import com.ytlite.player.data.network.InnerTubeApi
import com.ytlite.player.data.network.InnerTubeConfig
import com.ytlite.player.data.network.NetworkConfig
import com.ytlite.player.data.network.YouTubeNetworkException
import com.ytlite.player.data.parser.FeedParser
import com.ytlite.player.data.parser.MusicAlbumRelease
import com.ytlite.player.data.parser.MusicNewReleasesParser
import com.ytlite.player.data.parser.RelatedVideoParser
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import org.json.JSONObject

data class VideoPlaybackBundle(
    val playback: VideoPlayback?,
    val rawMessage: JSONObject?,
    val errorMessage: String? = null,
)

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
        if (searchQuery == FEED_QUERY_MUSIC_NEW_RELEASES) {
            return@withContext ExtractionResult.Error(
                "Use fetchMusicNewReleaseAlbumsFeed for new-release continuation",
            )
        }
        runFeedRequest {
            val page = when {
                searchQuery == null ->
                    FeedParser.parse(innerTubeApi.browseHome(continuation = continuation))
                else ->
                    FeedParser.parse(innerTubeApi.searchVideos(searchQuery, continuation))
            }
            page ?: throw YouTubeNetworkException("No videos in continuation response")
        }
    }

    /**
     * YouTube Music [new releases / albums](https://music.youtube.com/new_releases/albums):
     * Album/EP → album card entry; Single → track item.
     */
    suspend fun fetchMusicNewReleaseAlbumsFeed(
        offset: Int = 0,
        albumsPerPage: Int = NEW_RELEASE_ALBUMS_PER_PAGE,
    ): ExtractionResult<HomeFeedPage> = withContext(Dispatchers.IO) {
        try {
            val response = innerTubeApi.browseMusic(
                browseId = InnerTubeConfig.BROWSE_ID_MUSIC_NEW_RELEASES_ALBUMS,
            )
            val albums = MusicNewReleasesParser.parseAlbumReleases(response)
            if (albums.isEmpty()) {
                return@withContext ExtractionResult.Error("No new-release albums found")
            }
            val pageAlbums = albums.drop(offset.coerceAtLeast(0)).take(albumsPerPage)
            if (pageAlbums.isEmpty()) {
                return@withContext ExtractionResult.Error("No more new-release albums")
            }
            val items = coroutineScope {
                pageAlbums.map { release ->
                    async { mapNewReleaseItem(release) }
                }.awaitAll().filterNotNull()
            }
            if (items.isEmpty()) {
                return@withContext ExtractionResult.Error(
                    "No recommended videos found. Please try again later.",
                )
            }
            val nextOffset = offset.coerceAtLeast(0) + pageAlbums.size
            ExtractionResult.Success(
                HomeFeedPage(
                    items = items,
                    continuation = if (nextOffset < albums.size) {
                        "$NEW_RELEASE_CONTINUATION_PREFIX$nextOffset"
                    } else {
                        null
                    },
                ),
            )
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

    suspend fun fetchMusicAlbumTracks(
        browseId: String,
        albumTitle: String = "",
        artistFallback: String = "",
        thumbnailFallback: String = "",
    ): ExtractionResult<List<com.ytlite.player.data.model.VideoItem>> =
        withContext(Dispatchers.IO) {
            if (browseId.isBlank()) {
                return@withContext ExtractionResult.Error("Album ID is empty")
            }
            try {
                val response = innerTubeApi.browseMusic(browseId = browseId)
                val tracks = MusicNewReleasesParser.parseAlbumTracks(
                    response = response,
                    albumTitle = albumTitle,
                    artistFallback = artistFallback,
                    thumbnailFallback = thumbnailFallback,
                )
                if (tracks.isEmpty()) {
                    ExtractionResult.Error("No album tracks found")
                } else {
                    ExtractionResult.Success(tracks)
                }
            } catch (e: Exception) {
                ExtractionResult.Error(
                    message = "Failed to load album tracks",
                    cause = e,
                )
            }
        }

    private fun mapNewReleaseItem(release: MusicAlbumRelease): HomeFeedItem? {
        return if (release.isSingle) {
            val tracks = runCatching {
                val albumResponse = innerTubeApi.browseMusic(browseId = release.browseId)
                MusicNewReleasesParser.parseAlbumTracks(
                    response = albumResponse,
                    albumTitle = release.title,
                    artistFallback = release.artistName,
                    thumbnailFallback = release.thumbnailUrl,
                )
            }.getOrElse { emptyList() }
            val track = tracks.firstOrNull() ?: return null
            HomeFeedItem.Track(
                video = track.copy(
                    thumbnailUrl = release.thumbnailUrl.ifBlank { track.thumbnailUrl },
                    channelName = release.artistName.ifBlank { track.channelName },
                    publishedTimeText = release.releaseType.ifBlank { "Single" },
                ),
            )
        } else {
            HomeFeedItem.Album(
                browseId = release.browseId,
                playlistId = release.playlistId,
                title = release.title,
                artistName = release.artistName,
                thumbnailUrl = release.thumbnailUrl,
                releaseType = release.releaseType.ifBlank { "Album" },
            )
        }
    }

    suspend fun fetchVideoPlaybackBundle(
        videoId: String,
        rawMessage: JSONObject? = null,
    ): VideoPlaybackBundle = withContext(Dispatchers.IO) {
        if (videoId.isBlank()) {
            return@withContext VideoPlaybackBundle(
                playback = null,
                rawMessage = null,
                errorMessage = "Video ID is empty",
            )
        }
        try {
            val message = rawMessage ?: jsClient.extractVideo(videoId)
            val playback = JsResultMapper.toVideoPlayback(message)
            if (playback != null) {
                VideoPlaybackBundle(
                    playback = playback,
                    rawMessage = message,
                )
            } else {
                VideoPlaybackBundle(
                    playback = null,
                    rawMessage = message,
                    errorMessage = JsResultMapper.playbackErrorMessage(message)
                        ?: "Unable to parse playable mp4 URL from JS extractor",
                )
            }
        } catch (e: Exception) {
            VideoPlaybackBundle(
                playback = null,
                rawMessage = null,
                errorMessage = "Failed to load video playback",
            )
        }
    }

    suspend fun fetchVideoPlayback(
        videoId: String,
    ): ExtractionResult<VideoPlayback> = withContext(Dispatchers.IO) {
        val bundle = fetchVideoPlaybackBundle(videoId)
        val playback = bundle.playback
        if (playback != null) {
            ExtractionResult.Success(playback)
        } else {
            ExtractionResult.Error(
                message = bundle.errorMessage ?: "Failed to load video playback",
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
    ): ExtractionResult<List<com.ytlite.player.data.model.VideoItem>> =
        fetchMusicRelatedVideos(videoId).let { music ->
            if (music is ExtractionResult.Success) music
            else fetchWwwRelatedVideos(videoId, extractMessage)
        }

    /** youtube.com watch/next related (for Up next queue outside playlist context). */
    suspend fun fetchWwwRelatedVideos(
        videoId: String,
        extractMessage: JSONObject? = null,
    ): ExtractionResult<List<com.ytlite.player.data.model.VideoItem>> = withContext(Dispatchers.IO) {
        if (videoId.isBlank()) {
            return@withContext ExtractionResult.Error("Video ID is empty")
        }
        try {
            extractMessage?.let { message ->
                val fromJs = RelatedVideoParser.parseFromJsExtract(message, excludeVideoId = videoId)
                Log.d(TAG, "fetchWwwRelatedVideos jsPath count=${fromJs.size} videoId=$videoId")
                if (fromJs.isNotEmpty()) {
                    return@withContext ExtractionResult.Success(fromJs)
                }
            }
            val response = innerTubeApi.fetchWatchNext(videoId)
            val lockupCount = RelatedVideoParser.countLockupViewModels(response)
            Log.d(TAG, "fetchWwwRelatedVideos lockupViewModels=$lockupCount videoId=$videoId")
            val related = RelatedVideoParser.parse(response, excludeVideoId = videoId)
            Log.d(TAG, "fetchWwwRelatedVideos mapped=${related.size} videoId=$videoId")
            if (related.isEmpty()) {
                ExtractionResult.Error("No related videos found")
            } else {
                ExtractionResult.Success(related)
            }
        } catch (e: Exception) {
            Log.e(TAG, "fetchWwwRelatedVideos failed videoId=$videoId", e)
            ExtractionResult.Error(
                message = "Failed to load related videos",
                cause = e,
            )
        }
    }

    /** music.youtube.com RDAMVM radio (for Related tab). */
    suspend fun fetchMusicRelatedVideos(
        videoId: String,
    ): ExtractionResult<List<com.ytlite.player.data.model.VideoItem>> = withContext(Dispatchers.IO) {
        if (videoId.isBlank()) {
            return@withContext ExtractionResult.Error("Video ID is empty")
        }
        try {
            val musicResponse = innerTubeApi.fetchMusicRadioNext(videoId)
            val fromMusic = RelatedVideoParser.parse(musicResponse, excludeVideoId = videoId)
            Log.d(TAG, "fetchMusicRelatedVideos count=${fromMusic.size} videoId=$videoId")
            if (fromMusic.isEmpty()) {
                ExtractionResult.Error("No music related videos found")
            } else {
                ExtractionResult.Success(fromMusic)
            }
        } catch (e: Exception) {
            Log.e(TAG, "fetchMusicRelatedVideos failed videoId=$videoId", e)
            ExtractionResult.Error(
                message = "Failed to load music related videos",
                cause = e,
            )
        }
    }

    companion object {
        private const val TAG = "ExtractionRepository"

        /** Sentinel used by Home when loading Music new-release albums. */
        const val FEED_QUERY_MUSIC_NEW_RELEASES = "__music_new_releases_albums__"

        private const val NEW_RELEASE_ALBUMS_PER_PAGE = 20
        private const val NEW_RELEASE_CONTINUATION_PREFIX = "nr_albums:"

        fun parseNewReleaseOffset(continuation: String): Int {
            return continuation
                .removePrefix(NEW_RELEASE_CONTINUATION_PREFIX)
                .toIntOrNull()
                ?: 0
        }

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
