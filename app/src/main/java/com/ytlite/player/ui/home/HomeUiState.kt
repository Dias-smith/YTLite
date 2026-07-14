package com.ytlite.player.ui.home

import androidx.compose.runtime.Immutable
import com.ytlite.player.data.model.HomeFeedItem
import com.ytlite.player.data.model.VideoItem

@Immutable
data class AlbumBrowseState(
    val album: HomeFeedItem.Album,
    val tracks: List<VideoItem> = emptyList(),
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
)

@Immutable
data class HomeUiState(
    val items: List<HomeFeedItem> = emptyList(),
    val categories: List<FeedCategory> = HomeCategories.items,
    val selectedCategoryId: String = HomeCategories.defaultId,
    val feedSearchQuery: String? = null,
    val isLoading: Boolean = false,
    val isLoadingMore: Boolean = false,
    val errorMessage: String? = null,
    val continuation: String? = null,
    val albumBrowse: AlbumBrowseState? = null,
)
