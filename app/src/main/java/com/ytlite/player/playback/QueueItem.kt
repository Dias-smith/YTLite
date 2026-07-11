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
    val album: String? = null,
    val year: String? = null,
) {
    fun subtitleLine(): String = com.ytlite.player.data.repository.LibraryItemMapper.formatSongSubtitle(
        artist = channelName,
        album = album,
        year = year,
    ).ifBlank {
        listOfNotNull(
            channelName.takeIf { it.isNotBlank() },
            viewCountText?.takeIf { it.isNotBlank() },
            publishedTimeText?.takeIf { it.isNotBlank() },
        ).joinToString(" · ")
    }

    fun toTrackActionContext(showRemoveFromQueue: Boolean = false) =
        com.ytlite.player.ui.trackaction.TrackActionContext.fromQueueItem(this, showRemoveFromQueue)
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
