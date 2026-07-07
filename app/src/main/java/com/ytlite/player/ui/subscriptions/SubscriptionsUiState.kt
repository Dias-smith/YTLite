package com.ytlite.player.ui.subscriptions

import androidx.compose.runtime.Immutable
import com.ytlite.player.data.model.VideoItem
import com.ytlite.player.data.youtube.YoutubeSessionState

@Immutable
data class SubscriptionsUiState(
    val videos: List<VideoItem> = emptyList(),
    val continuation: String? = null,
    val isLoading: Boolean = false,
    val isLoadingMore: Boolean = false,
    val errorMessage: String? = null,
    val needsYoutubeReauth: Boolean = false,
    val youtubeSessionState: YoutubeSessionState = YoutubeSessionState.Disconnected,
    val showChannelList: Boolean = false,
)
