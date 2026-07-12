package com.ytlite.player.ui.library

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.ytlite.player.data.model.LibraryFilterChip
import com.ytlite.player.data.model.LibraryItem
import com.ytlite.player.data.model.LibraryViewMode

@Composable
fun LibraryContentView(
    items: List<LibraryItem>,
    viewMode: LibraryViewMode,
    selectedFilter: LibraryFilterChip,
    onItemClick: (LibraryItem) -> Unit,
    onSongMoreClick: (LibraryItem.Song) -> Unit,
    onPlaylistMoreClick: (LibraryItem.Playlist) -> Unit,
    onFindMusic: () -> Unit,
    isPlaylistReorderMode: Boolean = false,
    onPlaylistReorder: ((from: Int, to: Int) -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    if (items.isEmpty()) {
        LibraryEmptyState(
            filter = selectedFilter,
            onFindMusic = onFindMusic,
            modifier = modifier.fillMaxWidth(),
        )
        return
    }

    val playlistReorderEnabled =
        isPlaylistReorderMode &&
            selectedFilter == LibraryFilterChip.PLAYLISTS &&
            viewMode == LibraryViewMode.LIST
    val playlists = items.filterIsInstance<LibraryItem.Playlist>()

    when (viewMode) {
        LibraryViewMode.LIST -> {
            LazyColumn(
                modifier = modifier.fillMaxSize(),
                contentPadding = PaddingValues(bottom = 88.dp),
            ) {
                items(items = items, key = { it.id }) { item ->
                    val index = playlists.indexOfFirst { it.id == item.id }.takeIf { it >= 0 } ?: 0
                    LibraryRowItem(
                        item = item,
                        onClick = { onItemClick(item) },
                        onMoreClick = when (item) {
                            is LibraryItem.Song -> { { onSongMoreClick(item) } }
                            is LibraryItem.Playlist -> { { onPlaylistMoreClick(item) } }
                            else -> null
                        },
                        reorderMode = playlistReorderEnabled && item is LibraryItem.Playlist,
                        index = index,
                        itemCount = playlists.size,
                        playlists = playlists,
                        onDrag = onPlaylistReorder,
                    )
                }
            }
        }
        LibraryViewMode.GRID -> {
            LazyVerticalGrid(
                columns = GridCells.Fixed(2),
                modifier = modifier.fillMaxSize(),
                contentPadding = PaddingValues(bottom = 88.dp, start = 8.dp, end = 8.dp),
            ) {
                items(items = items, key = { it.id }) { item ->
                    LibraryGridItem(
                        item = item,
                        onClick = { onItemClick(item) },
                    )
                }
            }
        }
    }
}
