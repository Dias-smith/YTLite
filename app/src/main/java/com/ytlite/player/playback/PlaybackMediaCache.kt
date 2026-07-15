package com.ytlite.player.playback

import android.content.Context
import androidx.media3.common.util.UnstableApi
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.cache.Cache
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import java.io.File

@UnstableApi
object PlaybackMediaCache {

    @Volatile
    private var cache: SimpleCache? = null

    fun get(context: Context): Cache {
        cache?.let { return it }
        return synchronized(this) {
            cache ?: create(context.applicationContext).also { cache = it }
        }
    }

    fun removeResource(context: Context, cacheKey: String) {
        runCatching {
            get(context).removeResource(cacheKey)
        }
    }

    fun release() {
        synchronized(this) {
            cache?.release()
            cache = null
        }
    }

    private fun create(context: Context): SimpleCache {
        val directory = File(context.cacheDir, "media_cache").apply { mkdirs() }
        val databaseProvider = StandaloneDatabaseProvider(context)
        val maxBytes = PlaybackCachePolicy.maxCacheBytesFor(DeviceRam.isLowRamDevice(context))
        return SimpleCache(
            directory,
            LeastRecentlyUsedCacheEvictor(maxBytes),
            databaseProvider,
        )
    }
}
