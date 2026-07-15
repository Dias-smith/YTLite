package com.ytlite.player.playback

/**
 * Rules for whether a played stream should be written into local media cache.
 */
object PlaybackCachePolicy {
    /** Legacy constant — prefer [maxCacheBytesFor] for device-aware limits. */
    const val MaxCacheBytes = 512L * 1024L * 1024L
    const val LowRamMaxCacheBytes = 256L * 1024L * 1024L
    const val MaxCacheableDurationMs = 30L * 60L * 1000L
    const val HistoryOnlyRetentionMs = 3L * 24L * 60L * 60L * 1000L

    fun maxCacheBytesFor(isLowRam: Boolean): Long =
        if (isLowRam) LowRamMaxCacheBytes else MaxCacheBytes

    fun isCacheableDuration(durationMs: Long?): Boolean {
        if (durationMs == null || durationMs <= 0L) return true
        return durationMs <= MaxCacheableDurationMs
    }

    fun cacheKey(videoId: String, itag: Int?): String =
        if (itag != null) "$videoId:$itag" else videoId
}
