package com.ytlite.player.ui.subscriptions

import com.ytlite.player.data.model.SubscriptionChannel
import com.ytlite.player.data.model.VideoItem
import com.ytlite.player.data.remote.youtube.YoutubeYouPlaylistPreview

data class YoutubeYouUiState(
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val needsYoutubeReauth: Boolean = false,
    val hasLoadedOnce: Boolean = false,
    val lastLoadedUserId: String? = null,
    val displayName: String = "",
    val handle: String? = null,
    val avatarUrl: String? = null,
    val channelId: String? = null,
    val subscriptions: List<SubscriptionChannel> = emptyList(),
    val playlists: List<YoutubeYouPlaylistPreview> = emptyList(),
    val history: List<VideoItem> = emptyList(),
    val historyUnavailable: Boolean = true,
    val watchLater: List<VideoItem> = emptyList(),
    val watchLaterPlaylistId: String? = null,
    val watchLaterUnavailable: Boolean = true,
    val liked: List<VideoItem> = emptyList(),
    val likedPlaylistId: String? = null,
    val yourVideos: List<VideoItem> = emptyList(),
    val uploadsPlaylistId: String? = null,
)

data class YoutubePlaylistItemsUiState(
    val title: String = "",
    val playlistId: String = "",
    val videos: List<VideoItem> = emptyList(),
    val continuation: String? = null,
    val isLoading: Boolean = false,
    val isLoadingMore: Boolean = false,
    val errorMessage: String? = null,
)

data class YoutubePlaylistsListUiState(
    val playlists: List<YoutubeYouPlaylistPreview> = emptyList(),
    val continuation: String? = null,
    val isLoading: Boolean = false,
    val isLoadingMore: Boolean = false,
    val errorMessage: String? = null,
)
