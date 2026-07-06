package com.ytlite.player.data.model

import androidx.compose.runtime.Immutable

/**
 * Lightweight video card model for feed rendering.
 * Fields are kept minimal to reduce heap pressure on low-end devices.
 */
@Immutable
data class VideoItem(
    val videoId: String,
    val title: String,
    val channelName: String,
    val channelId: String?,
    val thumbnailUrl: String,
    val durationText: String?,
    val viewCountText: String?,
    val publishedTimeText: String?,
)
