package com.ytlite.player.playback

import androidx.compose.runtime.Immutable

@Immutable
data class QueueItem(
    val videoId: String,
    val title: String,
    val channelName: String,
    val thumbnailUrl: String,
    val streamUrl: String? = null,
) {
    fun toNowPlaying(streamUrl: String): NowPlaying = NowPlaying(
        videoId = videoId,
        title = title,
        channelName = channelName,
        streamUrl = streamUrl,
        thumbnailUrl = thumbnailUrl,
    )

    companion object {
        fun fromNowPlaying(nowPlaying: NowPlaying): QueueItem = QueueItem(
            videoId = nowPlaying.videoId,
            title = nowPlaying.title,
            channelName = nowPlaying.channelName,
            thumbnailUrl = nowPlaying.thumbnailUrl,
            streamUrl = nowPlaying.streamUrl,
        )
    }
}
