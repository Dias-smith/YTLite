package com.ytlite.player.ui.image

import android.content.Context
import android.graphics.Bitmap
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import coil.ImageLoader
import coil.disk.DiskCache
import coil.memory.MemoryCache
import coil.request.CachePolicy
import coil.request.ImageRequest

object YTLiteImageLoader {

    private const val DiskCacheDirectoryName = "image_cache"
    private const val DiskCacheMaxSizeBytes = 250L * 1024L * 1024L
    private const val MemoryCacheMaxSizePercent = 0.25

    @Volatile
    private var instance: ImageLoader? = null

    fun get(context: Context): ImageLoader {
        instance?.let { return it }
        return synchronized(this) {
            instance ?: create(context.applicationContext).also { instance = it }
        }
    }

    private fun create(context: Context): ImageLoader =
        ImageLoader.Builder(context)
            .memoryCache {
                MemoryCache.Builder(context)
                    .maxSizePercent(MemoryCacheMaxSizePercent)
                    .build()
            }
            .diskCache {
                DiskCache.Builder()
                    .directory(context.cacheDir.resolve(DiskCacheDirectoryName))
                    .maxSizeBytes(DiskCacheMaxSizeBytes)
                    .build()
            }
            // YouTube CDN often sends Cache-Control that would disable useful disk reuse.
            .respectCacheHeaders(false)
            .crossfade(false)
            .build()
}

@Composable
fun rememberYTLiteImageLoader(): ImageLoader {
    val context = LocalContext.current.applicationContext
    return remember(context) { YTLiteImageLoader.get(context) }
}

fun thumbnailRequest(
    context: Context,
    url: String,
): ImageRequest = ImageRequest.Builder(context)
    .data(url)
    .memoryCachePolicy(CachePolicy.ENABLED)
    .diskCachePolicy(CachePolicy.ENABLED)
    .networkCachePolicy(CachePolicy.ENABLED)
    .bitmapConfig(Bitmap.Config.RGB_565)
    .crossfade(false)
    .build()
