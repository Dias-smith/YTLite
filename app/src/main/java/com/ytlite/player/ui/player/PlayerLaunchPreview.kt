package com.ytlite.player.ui.player

import com.ytlite.player.data.model.LibraryItem
import com.ytlite.player.data.model.LibraryVideo
import com.ytlite.player.data.model.SearchResultItem
import com.ytlite.player.data.model.VideoItem
import com.ytlite.player.data.model.VideoPlayback
import com.ytlite.player.playback.NowPlaying
import com.ytlite.player.playback.QueueItem

object PlayerLaunchPreview {

    @Volatile
    private var pending: VideoItem? = null

    fun set(preview: VideoItem) {
        pending = preview
    }

    fun consume(videoId: String): VideoItem? {
        val preview = pending?.takeIf { it.videoId == videoId }
        if (preview != null) {
            pending = null
        }
        return preview
    }
}

fun VideoItem.toStubPlayback(): VideoPlayback = VideoPlayback(
    videoId = videoId,
    title = title,
    description = "",
    channelName = channelName,
    channelId = channelId.orEmpty(),
    formats = emptyList(),
    durationSeconds = 0L,
    viewCount = 0L,
)

fun videoPreview(
    videoId: String,
    title: String = "",
    channelName: String = "",
    channelId: String? = null,
    thumbnailUrl: String? = null,
): VideoItem = VideoItem(
    videoId = videoId,
    title = title,
    channelName = channelName,
    channelId = channelId,
    thumbnailUrl = thumbnailUrl ?: NowPlaying.thumbnailUrlFor(videoId),
    durationText = null,
    viewCountText = null,
    publishedTimeText = null,
)

fun LibraryVideo.toVideoItem(): VideoItem = VideoItem(
    videoId = videoId,
    title = title,
    channelName = channelName,
    channelId = channelId,
    thumbnailUrl = thumbnailUrl,
    durationText = durationText,
    viewCountText = viewCountText,
    publishedTimeText = publishedTimeText,
)

fun LibraryVideo.toQueueItem(): QueueItem = QueueItem(
    videoId = videoId,
    title = title,
    channelName = channelName,
    thumbnailUrl = thumbnailUrl,
    durationText = durationText,
    viewCountText = viewCountText,
    publishedTimeText = publishedTimeText,
    album = album,
    year = year,
    channelId = channelId,
)

fun SearchResultItem.Video.toVideoItem(): VideoItem = VideoItem(
    videoId = videoId,
    title = title,
    channelName = channelName.ifBlank { subtitle },
    channelId = channelId,
    thumbnailUrl = thumbnailUrl ?: NowPlaying.thumbnailUrlFor(videoId),
    durationText = null,
    viewCountText = viewCountText,
    publishedTimeText = null,
)

fun LibraryItem.Song.toVideoItem(): VideoItem = VideoItem(
    videoId = videoId,
    title = title,
    channelName = artistName.ifBlank { subtitle },
    channelId = channelId,
    thumbnailUrl = coverUrl ?: NowPlaying.thumbnailUrlFor(videoId),
    durationText = null,
    viewCountText = null,
    publishedTimeText = year,
)

fun LibraryItem.Song.toQueueItem(): QueueItem = QueueItem(
    videoId = videoId,
    title = title,
    channelName = artistName.ifBlank { subtitle },
    thumbnailUrl = coverUrl ?: NowPlaying.thumbnailUrlFor(videoId),
    album = album,
    year = year,
    channelId = channelId,
)

fun QueueItem.toVideoItem(): VideoItem = VideoItem(
    videoId = videoId,
    title = title,
    channelName = channelName,
    channelId = channelId,
    thumbnailUrl = thumbnailUrl,
    durationText = durationText,
    viewCountText = viewCountText,
    publishedTimeText = publishedTimeText,
)

fun VideoItem.toQueueItem(): QueueItem = QueueItem(
    videoId = videoId,
    title = title,
    channelName = channelName,
    thumbnailUrl = thumbnailUrl,
    durationText = durationText,
    viewCountText = viewCountText,
    publishedTimeText = publishedTimeText,
    channelId = channelId,
)
