package com.ytlite.player.ui.library

import androidx.compose.runtime.Immutable
import com.ytlite.player.data.auth.UserSession
import com.ytlite.player.data.model.DataSource
import com.ytlite.player.data.model.LibraryFilterChip
import com.ytlite.player.data.model.LibraryItem
import com.ytlite.player.data.model.LibrarySort
import com.ytlite.player.data.model.LibraryViewMode

@Immutable
data class LibraryUiState(
    val session: UserSession? = null,
    val items: List<LibraryItem> = emptyList(),
    val selectedFilter: LibraryFilterChip = LibraryFilterChip.PLAYLISTS,
    val sort: LibrarySort = LibrarySort.RECENT_ACTIVITY,
    val viewMode: LibraryViewMode = LibraryViewMode.LIST,
    val visibleChips: List<LibraryFilterChip> = emptyList(),
    val isLoading: Boolean = true,
    val isPlaylistReorderMode: Boolean = false,
    val isSelectionMode: Boolean = false,
    val selectedIds: Set<String> = emptySet(),
    val pendingSnackbar: String? = null,
    val downloadedCount: Int = 0,
) {
    val selectedCount: Int get() = selectedIds.size

    companion object {
        fun supportsMultiSelect(filter: LibraryFilterChip): Boolean =
            filter == LibraryFilterChip.SONGS || filter == LibraryFilterChip.PLAYLISTS

        /** System / YouTube playlists cannot be selected for batch delete. */
        fun isSelectable(item: LibraryItem): Boolean = when (item) {
            is LibraryItem.Song -> true
            is LibraryItem.Playlist ->
                item.systemType == null && item.source == DataSource.LOCAL
            else -> false
        }
    }
}
