package com.ytlite.player.ui.image

import android.graphics.Bitmap
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import coil.ImageLoader
import coil.disk.DiskCache
import coil.memory.MemoryCache
import coil.request.ImageRequest

@Composable
fun rememberYTLiteImageLoader(): ImageLoader {
    val context = LocalContext.current.applicationContext
    return remember {
        ImageLoader.Builder(context)
            .memoryCache {
                MemoryCache.Builder(context)
                    .maxSizePercent(0.15)
                    .build()
            }
            .diskCache {
                DiskCache.Builder()
                    .directory(context.cacheDir.resolve("image_cache"))
                    .maxSizePercent(0.02)
                    .build()
            }
            .crossfade(false)
            .build()
    }
}

fun thumbnailRequest(
    context: android.content.Context,
    url: String,
): ImageRequest = ImageRequest.Builder(context)
    .data(url)
    .bitmapConfig(Bitmap.Config.RGB_565)
    .crossfade(false)
    .build()
