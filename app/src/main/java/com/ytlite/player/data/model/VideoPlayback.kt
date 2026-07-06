package com.ytlite.player.data.model

import androidx.compose.runtime.Immutable

@Immutable
data class VideoPlayback(
    val videoId: String,
    val title: String,
    val description: String,
    val channelName: String,
    val channelId: String,
    val streamUrl: String,
    val durationSeconds: Long,
    val viewCount: Long,
)
