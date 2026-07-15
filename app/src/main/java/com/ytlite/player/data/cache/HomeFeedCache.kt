package com.ytlite.player.data.cache

import android.content.Context
import android.util.Log
import com.ytlite.player.data.model.HomeFeedItem
import com.ytlite.player.data.model.HomeFeedPage
import com.ytlite.player.data.model.VideoItem
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File

@Serializable
data class CachedHomeFeedSnapshot(
    val categoryId: String,
    val feedSearchQuery: String? = null,
    val continuation: String? = null,
    val items: List<CachedHomeFeedItemDto> = emptyList(),
    val cachedAtEpochMs: Long = 0L,
)

@Serializable
sealed class CachedHomeFeedItemDto {
    @Serializable
    @SerialName("track")
    data class Track(
        val videoId: String,
        val title: String,
        val channelName: String,
        val channelId: String? = null,
        val thumbnailUrl: String,
        val durationText: String? = null,
        val viewCountText: String? = null,
        val publishedTimeText: String? = null,
    ) : CachedHomeFeedItemDto()

    @Serializable
    @SerialName("album")
    data class Album(
        val browseId: String,
        val playlistId: String? = null,
        val title: String,
        val artistName: String,
        val thumbnailUrl: String,
        val releaseType: String,
    ) : CachedHomeFeedItemDto()
}

/**
 * Disk + memory cache for home category feeds.
 * Speeds up cold start and category switches for the last viewed category.
 */
class HomeFeedCache(context: Context) {

    private val cacheDir = File(context.applicationContext.cacheDir, "home_feed").also { it.mkdirs() }
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }
    private val memory = LinkedHashMap<String, CachedHomeFeedSnapshot>(16, 0.75f, true)
    private val mutex = Mutex()

    suspend fun read(categoryId: String): CachedHomeFeedSnapshot? = mutex.withLock {
        memory[categoryId]?.let { return@withLock it }
        withContext(Dispatchers.IO) {
            val file = fileFor(categoryId)
            if (!file.exists()) return@withContext null
            runCatching {
                json.decodeFromString<CachedHomeFeedSnapshot>(file.readText()).also {
                    memory[categoryId] = it
                    trimMemory()
                }
            }.onFailure {
                Log.w(TAG, "Failed to read home feed cache categoryId=$categoryId", it)
                file.delete()
            }.getOrNull()
        }
    }

    suspend fun write(
        categoryId: String,
        page: HomeFeedPage,
        feedSearchQuery: String?,
    ) = mutex.withLock {
        val snapshot = CachedHomeFeedSnapshot(
            categoryId = categoryId,
            feedSearchQuery = feedSearchQuery,
            continuation = page.continuation,
            items = page.items.map { it.toDto() },
            cachedAtEpochMs = System.currentTimeMillis(),
        )
        memory[categoryId] = snapshot
        trimMemory()
        withContext(Dispatchers.IO) {
            runCatching {
                fileFor(categoryId).writeText(json.encodeToString(snapshot))
            }.onFailure {
                Log.w(TAG, "Failed to write home feed cache categoryId=$categoryId", it)
            }
        }
    }

    companion object {
        private const val TAG = "HomeFeedCache"
        private const val MAX_MEMORY_ENTRIES = 8

        @Volatile
        private var instance: HomeFeedCache? = null

        fun getInstance(context: Context): HomeFeedCache =
            instance ?: synchronized(this) {
                instance ?: HomeFeedCache(context).also { instance = it }
            }
    }

    private fun fileFor(categoryId: String): File {
        val safe = categoryId.replace(Regex("[^A-Za-z0-9._-]"), "_")
        return File(cacheDir, "$safe.json")
    }

    private fun trimMemory() {
        while (memory.size > MAX_MEMORY_ENTRIES) {
            val eldest = memory.entries.iterator().next().key
            memory.remove(eldest)
        }
    }
}

fun CachedHomeFeedSnapshot.toHomeFeedPage(): HomeFeedPage =
    HomeFeedPage(
        items = items.mapNotNull { it.toDomain() },
        continuation = continuation,
    )

private fun HomeFeedItem.toDto(): CachedHomeFeedItemDto = when (this) {
    is HomeFeedItem.Track -> CachedHomeFeedItemDto.Track(
        videoId = video.videoId,
        title = video.title,
        channelName = video.channelName,
        channelId = video.channelId,
        thumbnailUrl = video.thumbnailUrl,
        durationText = video.durationText,
        viewCountText = video.viewCountText,
        publishedTimeText = video.publishedTimeText,
    )
    is HomeFeedItem.Album -> CachedHomeFeedItemDto.Album(
        browseId = browseId,
        playlistId = playlistId,
        title = title,
        artistName = artistName,
        thumbnailUrl = thumbnailUrl,
        releaseType = releaseType,
    )
}

private fun CachedHomeFeedItemDto.toDomain(): HomeFeedItem? = when (this) {
    is CachedHomeFeedItemDto.Track -> HomeFeedItem.Track(
        video = VideoItem(
            videoId = videoId,
            title = title,
            channelName = channelName,
            channelId = channelId,
            thumbnailUrl = thumbnailUrl,
            durationText = durationText,
            viewCountText = viewCountText,
            publishedTimeText = publishedTimeText,
        ),
    )
    is CachedHomeFeedItemDto.Album -> HomeFeedItem.Album(
        browseId = browseId,
        playlistId = playlistId,
        title = title,
        artistName = artistName,
        thumbnailUrl = thumbnailUrl,
        releaseType = releaseType,
    )
}
