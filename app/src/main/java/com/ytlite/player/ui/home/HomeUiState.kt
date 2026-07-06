package com.ytlite.player.ui.home

import androidx.compose.runtime.Immutable
import com.ytlite.player.data.model.VideoItem

@Immutable
data class HomeUiState(
    val videos: List<VideoItem> = emptyList(),
    val isLoading: Boolean = false,
    val isLoadingMore: Boolean = false,
    val errorMessage: String? = null,
    val continuation: String? = null,
)
