package com.ytlite.player.ui.library

import androidx.compose.runtime.Immutable
import com.ytlite.player.data.auth.UserSession
import com.ytlite.player.data.model.LibraryFilterChip
import com.ytlite.player.data.model.LibraryItem
import com.ytlite.player.data.model.LibrarySort
import com.ytlite.player.data.model.LibraryViewMode

@Immutable
data class LibraryUiState(
    val session: UserSession = UserSession.Guest(guestId = ""),
    val items: List<LibraryItem> = emptyList(),
    val selectedFilter: LibraryFilterChip = LibraryFilterChip.PLAYLISTS,
    val sort: LibrarySort = LibrarySort.RECENT_ACTIVITY,
    val viewMode: LibraryViewMode = LibraryViewMode.LIST,
    val visibleChips: List<LibraryFilterChip> = emptyList(),
    val isLoading: Boolean = true,
)
