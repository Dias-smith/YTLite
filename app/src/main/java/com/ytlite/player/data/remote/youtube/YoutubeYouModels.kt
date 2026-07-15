package com.ytlite.player.data.remote.youtube

import androidx.compose.runtime.Immutable
import com.ytlite.player.data.model.SubscriptionChannel
import com.ytlite.player.data.model.VideoItem

@Immutable
data class YoutubeYouPlaylistPreview(
    val playlistId: String,
    val title: String,
    val thumbnailUrl: String?,
    val itemCount: Int?,
    val privacyStatus: String?,
)

data class YoutubeYouPlaylistsPage(
    val playlists: List<YoutubeYouPlaylistPreview>,
    val continuation: String?,
)

@Immutable
data class YoutubeYouPageSnapshot(
    val subscriptions: List<SubscriptionChannel>,
    val subscriptionsContinuation: String?,
    val playlists: List<YoutubeYouPlaylistPreview>,
    val playlistsContinuation: String?,
    val history: List<VideoItem>,
    val historyContinuation: String?,
    val historyUnavailable: Boolean,
    val watchLater: List<VideoItem>,
    val watchLaterPlaylistId: String?,
    val watchLaterContinuation: String?,
    val watchLaterUnavailable: Boolean,
    val liked: List<VideoItem>,
    val likedPlaylistId: String?,
    val likedContinuation: String?,
    val yourVideos: List<VideoItem>,
    val uploadsPlaylistId: String?,
    val yourVideosContinuation: String?,
    val channelId: String?,
    val channelTitle: String?,
    val channelHandle: String?,
    val channelAvatarUrl: String?,
    /** True when OAuth token is missing/expired and Data API shelves cannot load. */
    val needsYoutubeReauth: Boolean = false,
)

/** One You-page section loaded via authenticated InnerTube. */
data class YoutubeYouInnerTubeSection(
    val videos: List<VideoItem>,
    val continuation: String?,
    val unavailable: Boolean,
)
