package com.ytlite.player.playback

import com.ytlite.player.data.model.VideoItem
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap

enum class RelatedCacheKind {
    Www,
    Music,
}

object UpNextCache {

    private const val TTL_MS = 10 * 60 * 1000L

    private data class Entry(
        val items: List<VideoItem>,
        val extractMessage: JSONObject?,
        val cachedAtMs: Long,
    )

    private val cache = ConcurrentHashMap<String, Entry>()

    fun get(videoId: String, kind: RelatedCacheKind = RelatedCacheKind.Www): List<VideoItem>? {
        evictExpired()
        val entry = cache[key(videoId, kind)] ?: return null
        return entry.items.takeIf { it.isNotEmpty() }
    }

    fun getExtractMessage(
        videoId: String,
        kind: RelatedCacheKind = RelatedCacheKind.Www,
    ): JSONObject? {
        evictExpired()
        return cache[key(videoId, kind)]?.extractMessage
    }

    fun put(
        videoId: String,
        items: List<VideoItem>,
        extractMessage: JSONObject?,
        kind: RelatedCacheKind = RelatedCacheKind.Www,
    ) {
        if (videoId.isBlank() || items.isEmpty()) return
        evictExpired()
        cache[key(videoId, kind)] = Entry(
            items = items,
            extractMessage = extractMessage,
            cachedAtMs = System.currentTimeMillis(),
        )
    }

    private fun key(videoId: String, kind: RelatedCacheKind): String = "$kind:$videoId"

    private fun evictExpired() {
        val now = System.currentTimeMillis()
        cache.entries.removeIf { (_, entry) ->
            now - entry.cachedAtMs > TTL_MS
        }
    }
}
