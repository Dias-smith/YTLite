package com.ytlite.player.playback

import androidx.compose.runtime.Immutable

@Immutable
data class QueueItem(
    val videoId: String,
    val title: String,
    val channelName: String,
    val thumbnailUrl: String,
    val streamUrl: String? = null,
    val durationText: String? = null,
    val viewCountText: String? = null,
    val publishedTimeText: String? = null,
) {
    fun subtitleLine(): String = listOfNotNull(
        channelName.takeIf { it.isNotBlank() },
        viewCountText?.takeIf { it.isNotBlank() },
        publishedTimeText?.takeIf { it.isNotBlank() },
    ).joinToString(" · ")

    fun toSongActionContext() = com.ytlite.player.ui.library.SongActionContext(
        videoId = videoId,
        title = title,
        channelName = channelName,
        thumbnailUrl = thumbnailUrl,
        playlistId = null,
        playlistSource = com.ytlite.player.data.model.DataSource.LOCAL,
    )
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
