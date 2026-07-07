package com.ytlite.player.ui.subscriptions

import androidx.compose.runtime.Immutable
import com.ytlite.player.data.model.SubscriptionChannel
import com.ytlite.player.data.model.VideoItem

@Immutable
data class ChannelVideosUiState(
    val channel: SubscriptionChannel,
    val videos: List<VideoItem> = emptyList(),
    val continuation: String? = null,
    val isLoading: Boolean = false,
    val isLoadingMore: Boolean = false,
    val errorMessage: String? = null,
)
