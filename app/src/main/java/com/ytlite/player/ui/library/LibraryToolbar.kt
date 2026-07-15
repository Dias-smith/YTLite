package com.ytlite.player.ui.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.ViewList
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.Sort
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.ytlite.player.R
import com.ytlite.player.data.model.LibraryFilterChip
import com.ytlite.player.data.model.LibrarySort
import com.ytlite.player.data.model.LibraryViewMode

@Composable
fun LibraryToolbar(
    itemCount: Int,
    selectedFilter: LibraryFilterChip,
    sort: LibrarySort,
    viewMode: LibraryViewMode,
    isPlaylistReorderMode: Boolean,
    multiSelectEnabled: Boolean,
    onSetSort: (LibrarySort) -> Unit,
    onEnterPlaylistReorder: () -> Unit,
    onEnterSelectionMode: () -> Unit,
    onToggleViewMode: () -> Unit,
    modifier: Modifier = Modifier,
) {
    if (isPlaylistReorderMode) return

    var sortMenuExpanded by remember { mutableStateOf(false) }

    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(start = 16.dp, end = 4.dp, top = 0.dp, bottom = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            text = stringResource(R.string.library_item_count, itemCount),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box {
                IconButton(onClick = { sortMenuExpanded = true }) {
                    Icon(
                        imageVector = Icons.Outlined.Sort,
                        contentDescription = stringResource(R.string.library_sort_menu),
                    )
                }
                DropdownMenu(
                    expanded = sortMenuExpanded,
                    onDismissRequest = { sortMenuExpanded = false },
                ) {
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.library_sort_recent_activity)) },
                        onClick = {
                            onSetSort(LibrarySort.RECENT_ACTIVITY)
                            sortMenuExpanded = false
                        },
                        trailingIcon = {
                            if (sort == LibrarySort.RECENT_ACTIVITY) {
                                Text("✓", color = MaterialTheme.colorScheme.primary)
                            }
                        },
                    )
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.library_sort_recently_saved)) },
                        onClick = {
                            onSetSort(LibrarySort.RECENTLY_SAVED)
                            sortMenuExpanded = false
                        },
                        trailingIcon = {
                            if (sort == LibrarySort.RECENTLY_SAVED) {
                                Text("✓", color = MaterialTheme.colorScheme.primary)
                            }
                        },
                    )
                    if (selectedFilter == LibraryFilterChip.PLAYLISTS) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.library_playlist_reorder)) },
                            onClick = {
                                onEnterPlaylistReorder()
                                sortMenuExpanded = false
                            },
                        )
                    }
                }
            }
            if (multiSelectEnabled) {
                IconButton(onClick = onEnterSelectionMode) {
                    Icon(
                        imageVector = Icons.Outlined.Checklist,
                        contentDescription = stringResource(R.string.library_multi_select),
                    )
                }
            }
            IconButton(onClick = onToggleViewMode) {
                Icon(
                    imageVector = if (viewMode == LibraryViewMode.LIST) {
                        Icons.Default.GridView
                    } else {
                        Icons.Default.ViewList
                    },
                    contentDescription = stringResource(R.string.library_toggle_view_mode),
                )
            }
        }
    }
}
