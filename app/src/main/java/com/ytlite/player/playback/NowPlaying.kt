package com.ytlite.player.playback

import androidx.compose.runtime.Immutable

@Immutable
data class NowPlaying(
    val videoId: String,
    val title: String,
    val channelName: String,
    val streamUrl: String,
    val thumbnailUrl: String,
    val itag: Int? = null,
    /** Known duration before player reports one; null/0 means unknown. */
    val durationMs: Long? = null,
    val channelId: String? = null,
) {
    companion object {
        fun thumbnailUrlFor(videoId: String): String =
            "https://i.ytimg.com/vi/$videoId/hqdefault.jpg"
    }
}
