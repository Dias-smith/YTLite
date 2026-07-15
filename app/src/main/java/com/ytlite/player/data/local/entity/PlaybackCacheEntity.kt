package com.ytlite.player.data.local.entity

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "playback_media_cache")
data class PlaybackCacheEntity(
    @PrimaryKey val videoId: String,
    val cacheKey: String,
    val itag: Int?,
    val lastPlayedAt: Long,
    /** Null while still in any non-History playlist; otherwise when it became History-only. */
    val historyOnlySince: Long? = null,
)
