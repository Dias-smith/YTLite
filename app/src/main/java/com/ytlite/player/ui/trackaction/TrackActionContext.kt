package com.ytlite.player.ui.trackaction

import androidx.compose.runtime.Immutable
import com.ytlite.player.data.local.model.PlaylistTrackDetailRow
import com.ytlite.player.data.model.DataSource
import com.ytlite.player.data.model.LibraryItem
import com.ytlite.player.data.model.LibraryVideo
import com.ytlite.player.data.model.SearchResultItem
import com.ytlite.player.data.model.VideoItem
import com.ytlite.player.playback.QueueItem

enum class TrackActionSource {
    LIBRARY,
    QUEUE,
    FEED,
    SEARCH,
    PLAYER_UP_NEXT,
}

@Immutable
data class TrackActionContext(
    val videoId: String,
    val title: String,
    val channelName: String,
    val thumbnailUrl: String,
    val channelId: String? = null,
    val album: String? = null,
    val year: String? = null,
    val durationText: String? = null,
    val viewCountText: String? = null,
    val publishedTimeText: String? = null,
    val source: TrackActionSource = TrackActionSource.LIBRARY,
    val playlistId: String? = null,
    val playlistSource: DataSource = DataSource.LOCAL,
    val showRemoveFromQueue: Boolean = false,
) {
    fun toQueueItem() = QueueItem(
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

    fun toLibraryVideo() = LibraryVideo(
        videoId = videoId,
        title = title,
        channelName = channelName,
        channelId = channelId,
        thumbnailUrl = thumbnailUrl,
        album = album,
        year = year,
        durationText = durationText,
        viewCountText = viewCountText,
        publishedTimeText = publishedTimeText,
    )

    companion object {
        fun fromQueueItem(item: QueueItem, showRemoveFromQueue: Boolean = true) = TrackActionContext(
            videoId = item.videoId,
            title = item.title,
            channelName = item.channelName,
            thumbnailUrl = item.thumbnailUrl,
            channelId = item.channelId,
            durationText = item.durationText,
            viewCountText = item.viewCountText,
            publishedTimeText = item.publishedTimeText,
            album = item.album,
            year = item.year,
            source = TrackActionSource.QUEUE,
            showRemoveFromQueue = showRemoveFromQueue,
        )

        fun fromVideoItem(video: VideoItem, source: TrackActionSource = TrackActionSource.FEED) =
            TrackActionContext(
                videoId = video.videoId,
                title = video.title,
                channelName = video.channelName,
                thumbnailUrl = video.thumbnailUrl,
                channelId = video.channelId,
                durationText = video.durationText,
                viewCountText = video.viewCountText,
                publishedTimeText = video.publishedTimeText,
                source = source,
            )

        fun fromLibraryVideo(
            video: LibraryVideo,
            playlistId: String? = null,
            playlistSource: DataSource = DataSource.LOCAL,
        ) = TrackActionContext(
            videoId = video.videoId,
            title = video.title,
            channelName = video.channelName,
            thumbnailUrl = video.thumbnailUrl,
            channelId = video.channelId,
            album = video.album,
            year = video.year,
            durationText = video.durationText,
            viewCountText = video.viewCountText,
            publishedTimeText = video.publishedTimeText,
            source = TrackActionSource.LIBRARY,
            playlistId = playlistId,
            playlistSource = playlistSource,
        )

        fun fromLibraryItemSong(song: LibraryItem.Song) = TrackActionContext(
            videoId = song.videoId,
            title = song.title,
            channelName = song.artistName.ifBlank { song.subtitle },
            thumbnailUrl = song.coverUrl.orEmpty(),
            channelId = song.channelId,
            album = song.album,
            year = song.year,
            source = TrackActionSource.LIBRARY,
        )

        fun fromPlaylistTrack(
            track: PlaylistTrackDetailRow,
            playlistId: String,
            source: DataSource,
        ) = TrackActionContext(
            videoId = track.trackId,
            title = track.title,
            channelName = track.primaryArtistName.orEmpty(),
            thumbnailUrl = track.thumbnailUrl,
            channelId = track.primaryArtistId,
            album = track.album,
            year = track.year,
            durationText = track.durationText,
            source = TrackActionSource.LIBRARY,
            playlistId = playlistId,
            playlistSource = source,
        )

        fun fromSearchVideo(video: SearchResultItem.Video) = TrackActionContext(
            videoId = video.videoId,
            title = video.title,
            channelName = video.channelName.ifBlank { video.subtitle },
            thumbnailUrl = video.thumbnailUrl.orEmpty(),
            channelId = video.channelId,
            viewCountText = video.viewCountText,
            source = TrackActionSource.SEARCH,
        )
    }
}
