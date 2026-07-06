package com.ytlite.player.data.model

data class FeedPage(
    val videos: List<VideoItem>,
    val continuation: String?,
)
