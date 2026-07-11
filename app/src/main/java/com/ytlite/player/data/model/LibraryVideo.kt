package com.ytlite.player.data.model

import androidx.compose.runtime.Immutable

@Immutable
data class LibraryVideo(
    val videoId: String,
    val title: String,
    val channelName: String,
    val channelId: String? = null,
    val thumbnailUrl: String,
    val album: String? = null,
    val year: String? = null,
    val durationText: String? = null,
    val viewCountText: String? = null,
    val publishedTimeText: String? = null,
    val watchedAt: Long = 0L,
    val progressMs: Long = 0L,
)
