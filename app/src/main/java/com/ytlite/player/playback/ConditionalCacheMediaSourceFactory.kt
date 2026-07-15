package com.ytlite.player.playback

import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.source.MediaSource

/**
 * Routes media sources by URI:
 * - local file/content → [DefaultDataSource] (no HTTP cache)
 * - remote with [MediaItem.LocalConfiguration.customCacheKey] → [CacheDataSource]
 * - other remote → HTTP (or DefaultDataSource) without requiring a cache key
 */
@UnstableApi
class ConditionalCacheMediaSourceFactory(
    context: Context,
    private val httpDataSourceFactory: DataSource.Factory,
    cacheDataSourceFactory: CacheDataSource.Factory,
) : MediaSource.Factory {

    private val localDataSourceFactory = DefaultDataSource.Factory(context, httpDataSourceFactory)
    private val localFactory = DefaultMediaSourceFactory(localDataSourceFactory)
    private val cachedFactory = DefaultMediaSourceFactory(cacheDataSourceFactory)
    private val networkFactory = DefaultMediaSourceFactory(httpDataSourceFactory)

    override fun setDrmSessionManagerProvider(
        drmSessionManagerProvider: androidx.media3.exoplayer.drm.DrmSessionManagerProvider,
    ): MediaSource.Factory {
        localFactory.setDrmSessionManagerProvider(drmSessionManagerProvider)
        cachedFactory.setDrmSessionManagerProvider(drmSessionManagerProvider)
        networkFactory.setDrmSessionManagerProvider(drmSessionManagerProvider)
        return this
    }

    override fun setLoadErrorHandlingPolicy(
        loadErrorHandlingPolicy: androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy,
    ): MediaSource.Factory {
        localFactory.setLoadErrorHandlingPolicy(loadErrorHandlingPolicy)
        cachedFactory.setLoadErrorHandlingPolicy(loadErrorHandlingPolicy)
        networkFactory.setLoadErrorHandlingPolicy(loadErrorHandlingPolicy)
        return this
    }

    override fun getSupportedTypes(): IntArray = localFactory.supportedTypes

    override fun createMediaSource(mediaItem: MediaItem): MediaSource {
        val uri = mediaItem.localConfiguration?.uri
        val scheme = uri?.scheme?.lowercase().orEmpty()
        if (scheme == "file" || scheme == "content" || scheme == "asset" || scheme == "rawresource") {
            return localFactory.createMediaSource(mediaItem)
        }
        val cacheKey = mediaItem.localConfiguration?.customCacheKey
        return if (!cacheKey.isNullOrBlank()) {
            cachedFactory.createMediaSource(mediaItem)
        } else {
            networkFactory.createMediaSource(mediaItem)
        }
    }
}
