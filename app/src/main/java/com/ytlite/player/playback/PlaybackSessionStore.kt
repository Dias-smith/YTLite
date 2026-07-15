package com.ytlite.player.playback

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File

@Serializable
data class PersistedQueueItem(
    val videoId: String,
    val title: String,
    val channelName: String,
    val thumbnailUrl: String,
    val durationText: String? = null,
    val viewCountText: String? = null,
    val publishedTimeText: String? = null,
    val album: String? = null,
    val year: String? = null,
    val itag: Int? = null,
    val channelId: String? = null,
) {
    fun toQueueItem(): QueueItem = QueueItem(
        videoId = videoId,
        title = title,
        channelName = channelName,
        thumbnailUrl = thumbnailUrl,
        streamUrl = null,
        durationText = durationText,
        viewCountText = viewCountText,
        publishedTimeText = publishedTimeText,
        album = album,
        year = year,
        itag = itag,
        channelId = channelId,
    )

    companion object {
        fun from(item: QueueItem): PersistedQueueItem = PersistedQueueItem(
            videoId = item.videoId,
            title = item.title,
            channelName = item.channelName,
            thumbnailUrl = item.thumbnailUrl,
            durationText = item.durationText,
            viewCountText = item.viewCountText,
            publishedTimeText = item.publishedTimeText,
            album = item.album,
            year = item.year,
            itag = item.itag,
            channelId = item.channelId,
        )
    }
}

@Serializable
data class PlaybackSessionSnapshot(
    val items: List<PersistedQueueItem> = emptyList(),
    val currentIndex: Int = 0,
    val repeatMode: String = QueueRepeatMode.OFF.name,
    val shuffleEnabled: Boolean = false,
    val sourcePlaylistId: String? = null,
    val originalOrder: List<PersistedQueueItem>? = null,
    val positionMs: Long = 0L,
    val durationMs: Long = 0L,
)

/**
 * Persists the last play queue / current track / playback mode for cold-start restore.
 * Stream URLs are intentionally omitted (they expire); metadata is enough for the mini player.
 */
class PlaybackSessionStore(context: Context) {

    private val file = File(context.applicationContext.filesDir, FILE_NAME)
    private val mutex = Mutex()
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    suspend fun load(): PlaybackSessionSnapshot? = mutex.withLock {
        withContext(Dispatchers.IO) {
            if (!file.exists()) return@withContext null
            runCatching {
                json.decodeFromString<PlaybackSessionSnapshot>(file.readText())
            }.onFailure { error ->
                Log.w(TAG, "Failed to load playback session", error)
            }.getOrNull()
                ?.takeIf { it.items.isNotEmpty() }
        }
    }

    suspend fun save(snapshot: PlaybackSessionSnapshot) = mutex.withLock {
        withContext(Dispatchers.IO) {
            if (snapshot.items.isEmpty()) {
                if (file.exists()) file.delete()
                return@withContext
            }
            runCatching {
                file.writeText(json.encodeToString(snapshot))
            }.onFailure { error ->
                Log.w(TAG, "Failed to save playback session", error)
            }
        }
    }

    suspend fun clear() = mutex.withLock {
        withContext(Dispatchers.IO) {
            if (file.exists()) file.delete()
        }
    }

    companion object {
        private const val TAG = "PlaybackSessionStore"
        private const val FILE_NAME = "playback_session.json"

        @Volatile
        private var instance: PlaybackSessionStore? = null

        fun getInstance(context: Context): PlaybackSessionStore =
            instance ?: synchronized(this) {
                instance ?: PlaybackSessionStore(context).also { instance = it }
            }
    }
}
