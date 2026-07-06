package com.ytlite.player.data.local.entity

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "tracks")
data class TrackEntity(
    @PrimaryKey val trackId: String,
    val title: String,
    val durationSeconds: Int = 0,
    val durationText: String? = null,
    val thumbnailLow: String? = null,
    val thumbnailMedium: String? = null,
    val thumbnailHigh: String? = null,
    val viewCount: Long = 0L,
    val viewCountText: String? = null,
    val publishedText: String? = null,
    val primaryArtistId: String? = null,
    val primaryArtistName: String? = null,
)
