package com.ytlite.player.ui.subscriptions

import androidx.compose.runtime.Immutable
import com.ytlite.player.data.model.SubscriptionChannel

@Immutable
data class SubscriptionChannelsUiState(
    val channels: List<SubscriptionChannel> = emptyList(),
    val continuation: String? = null,
    val isLoading: Boolean = false,
    val isLoadingMore: Boolean = false,
    val errorMessage: String? = null,
)
