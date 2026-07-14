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
    val itag: Int? = null,
    val channelId: String? = null,
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
        itag = itag,
        durationMs = durationText?.let { parseDurationTextToMs(it) },
        channelId = channelId,
    )

    companion object {
        fun fromNowPlaying(nowPlaying: NowPlaying): QueueItem = QueueItem(
            videoId = nowPlaying.videoId,
            title = nowPlaying.title,
            channelName = nowPlaying.channelName,
            thumbnailUrl = nowPlaying.thumbnailUrl,
            streamUrl = nowPlaying.streamUrl,
            durationText = nowPlaying.durationMs
                ?.takeIf { it > 0L }
                ?.let { formatDurationMs(it) },
            itag = nowPlaying.itag,
            channelId = nowPlaying.channelId,
        )
    }
}

private fun parseDurationTextToMs(text: String): Long? {
    val parts = text.trim().split(':')
    if (parts.isEmpty() || parts.any { it.toLongOrNull() == null }) return null
    var total = 0L
    for (part in parts) {
        total = total * 60 + (part.toLongOrNull() ?: return null)
    }
    return total * 1000L
}

private fun formatDurationMs(durationMs: Long): String {
    val totalSeconds = (durationMs / 1000L).coerceAtLeast(0L)
    val hours = totalSeconds / 3600
    val minutes = (totalSeconds % 3600) / 60
    val seconds = totalSeconds % 60
    return if (hours > 0) {
        "%d:%02d:%02d".format(hours, minutes, seconds)
    } else {
        "%d:%02d".format(minutes, seconds)
    }
}
