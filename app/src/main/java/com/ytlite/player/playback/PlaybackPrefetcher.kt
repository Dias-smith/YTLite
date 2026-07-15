package com.ytlite.player.playback

import com.ytlite.player.data.parser.RelatedVideoParser
import com.ytlite.player.data.repository.ExtractionRepository
import com.ytlite.player.data.repository.VideoPlaybackBundle
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import java.util.concurrent.ConcurrentHashMap

object PlaybackPrefetcher {

    private const val TTL_MS = 5 * 60 * 1000L

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val cache = ConcurrentHashMap<String, PrefetchEntry>()

    private data class PrefetchEntry(
        val deferred: Deferred<VideoPlaybackBundle>,
        val startedAtMs: Long,
    )

    fun prefetch(videoId: String) {
        if (videoId.isBlank()) return
        evictExpired()
        cache.computeIfAbsent(videoId) {
            PrefetchEntry(
                deferred = scope.async {
                    val bundle = ExtractionRepository.getInstance().fetchVideoPlaybackBundle(videoId)
                    cacheUpNextFromBundle(videoId, bundle)
                    bundle
                },
                startedAtMs = System.currentTimeMillis(),
            )
        }
    }

    private fun cacheUpNextFromBundle(videoId: String, bundle: VideoPlaybackBundle) {
        val message = bundle.rawMessage ?: return
        val related = RelatedVideoParser.parseFromJsExtract(message, excludeVideoId = videoId)
        if (related.isNotEmpty()) {
            UpNextCache.put(videoId, related, message, kind = RelatedCacheKind.Www)
        }
    }

    suspend fun consumeBundle(videoId: String): VideoPlaybackBundle? {
        evictExpired()
        val entry = cache.remove(videoId) ?: return null
        return runCatching { entry.deferred.await() }.getOrNull()
    }

    private fun evictExpired() {
        val now = System.currentTimeMillis()
        cache.entries.removeIf { (_, entry) ->
            now - entry.startedAtMs > TTL_MS
        }
    }
}
