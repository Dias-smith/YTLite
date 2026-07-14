package com.ytlite.player.data.model

import androidx.compose.runtime.Immutable
import com.ytlite.player.playback.QueueItem

@Immutable
data class TrackMetadataSeed(
    val trackId: String,
    val title: String,
    val artistName: String,
    val thumbnailUrl: String,
    val album: String? = null,
    val year: String? = null,
    val channelId: String? = null,
) {
    fun toQueueItem() = QueueItem(
        videoId = trackId,
        title = title,
        channelName = artistName,
        thumbnailUrl = thumbnailUrl,
        album = album,
        year = year,
        channelId = channelId,
    )
}
