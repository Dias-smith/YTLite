package com.ytlite.player.ui.subscriptions

import androidx.compose.runtime.Immutable
import com.ytlite.player.data.model.SubscriptionChannel
import com.ytlite.player.data.model.VideoItem

@Immutable
data class SubscriptionsUiState(
    val videos: List<VideoItem> = emptyList(),
    val channels: List<SubscriptionChannel> = emptyList(),
    val continuation: String? = null,
    val channelsContinuation: String? = null,
    val isLoading: Boolean = false,
    val isLoadingMore: Boolean = false,
    val isLoadingMoreChannels: Boolean = false,
    val errorMessage: String? = null,
    val needsYoutubeReauth: Boolean = false,
    val hasLoadedOnce: Boolean = false,
    val lastLoadedUserId: String? = null,
)
