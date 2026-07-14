package com.ytlite.player.ui.library

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Deselect
import androidx.compose.material.icons.outlined.PlaylistAdd
import androidx.compose.material.icons.outlined.SelectAll
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import android.widget.Toast
import com.ytlite.player.R
import com.ytlite.player.data.model.LibraryFilterChip
import com.ytlite.player.data.model.LibraryItem
import com.ytlite.player.data.model.LibrarySort

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryHomeScreen(
    uiState: LibraryUiState,
    onProfileClick: () -> Unit,
    onSettingsClick: () -> Unit,
    onFilterSelected: (LibraryFilterChip) -> Unit,
    onSetSort: (LibrarySort) -> Unit,
    onToggleViewMode: () -> Unit,
    onItemClick: (LibraryItem) -> Unit,
    onToggleSelection: (String) -> Unit,
    onEnterSelectionMode: () -> Unit,
    onExitSelectionMode: () -> Unit,
    onSelectAll: () -> Unit = {},
    onDeselectAll: () -> Unit = {},
    onSongMoreClick: (LibraryItem.Song) -> Unit,
    onPlaylistMoreClick: (LibraryItem.Playlist) -> Unit,
    onChannelMoreClick: (LibraryItem.Channel) -> Unit = {},
    onFindMusic: () -> Unit,
    onNewPlaylist: () -> Unit,
    onEnterPlaylistReorder: () -> Unit = {},
    onExitPlaylistReorder: () -> Unit = {},
    onPlaylistOrderCommitted: ((List<LibraryItem.Playlist>) -> Unit)? = null,
    onBatchAddToPlaylist: () -> Unit = {},
    onConfirmDeleteSelected: () -> Unit = {},
    onSnackbarConsumed: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val snackbarHostState = remember { SnackbarHostState() }
    val context = LocalContext.current
    var showDeleteConfirm by remember { mutableStateOf(false) }

    LaunchedEffect(uiState.pendingSnackbar) {
        val message = uiState.pendingSnackbar ?: return@LaunchedEffect
        snackbarHostState.showSnackbar(message)
        onSnackbarConsumed()
    }

    val multiSelectSupported = LibraryUiState.supportsMultiSelect(uiState.selectedFilter)

    Scaffold(
        modifier = modifier.fillMaxSize(),
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            if (uiState.isSelectionMode) {
                TopAppBar(
                    title = {
                        Text(
                            text = stringResource(
                                R.string.library_n_selected,
                                uiState.selectedCount,
                            ),
                            maxLines = 1,
                            softWrap = false,
                            overflow = TextOverflow.Ellipsis,
                        )
                    },
                    navigationIcon = {
                        IconButton(onClick = onExitSelectionMode) {
                            Icon(
                                imageVector = Icons.Default.Close,
                                contentDescription = stringResource(R.string.library_cancel),
                            )
                        }
                    },
                    actions = {
                        IconButton(onClick = onSelectAll) {
                            Icon(
                                imageVector = Icons.Outlined.SelectAll,
                                contentDescription = stringResource(R.string.library_select_all),
                            )
                        }
                        IconButton(
                            onClick = onDeselectAll,
                            enabled = uiState.selectedCount > 0,
                        ) {
                            Icon(
                                imageVector = Icons.Outlined.Deselect,
                                contentDescription = stringResource(R.string.library_deselect_all),
                            )
                        }
                        if (uiState.selectedFilter == LibraryFilterChip.SONGS &&
                            uiState.selectedCount > 0
                        ) {
                            IconButton(onClick = onBatchAddToPlaylist) {
                                Icon(
                                    imageVector = Icons.Outlined.PlaylistAdd,
                                    contentDescription = stringResource(
                                        R.string.library_batch_add_playlist,
                                    ),
                                )
                            }
                        }
                        if (uiState.selectedCount > 0) {
                            IconButton(onClick = { showDeleteConfirm = true }) {
                                Icon(
                                    imageVector = Icons.Outlined.Delete,
                                    contentDescription = stringResource(
                                        R.string.library_batch_delete,
                                    ),
                                )
                            }
                        }
                    },
                )
            } else {
                TopAppBar(
                    title = { Text(text = stringResource(R.string.nav_library)) },
                    actions = {
                        IconButton(onClick = onProfileClick) {
                            Icon(
                                imageVector = Icons.Default.AccountCircle,
                                contentDescription = stringResource(R.string.account_switcher_title),
                            )
                        }
                        IconButton(onClick = onSettingsClick) {
                            Icon(
                                imageVector = Icons.Outlined.Settings,
                                contentDescription = stringResource(R.string.settings_title),
                            )
                        }
                    },
                )
            }
        },
        floatingActionButton = {
            if (
                uiState.selectedFilter == LibraryFilterChip.PLAYLISTS &&
                !uiState.isSelectionMode &&
                !uiState.isPlaylistReorderMode
            ) {
                FloatingActionButton(onClick = onNewPlaylist) {
                    Text(text = stringResource(R.string.library_new_fab))
                }
            }
        },
    ) { innerPadding ->
        androidx.compose.foundation.layout.Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
        ) {
            if (!uiState.isSelectionMode) {
                LibraryFilterChips(
                    visibleChips = uiState.visibleChips,
                    selectedFilter = uiState.selectedFilter,
                    onChipSelected = onFilterSelected,
                    isPlaylistReorderMode = uiState.isPlaylistReorderMode,
                    onExitPlaylistReorder = onExitPlaylistReorder,
                )
                LibraryToolbar(
                    itemCount = uiState.items.size,
                    selectedFilter = uiState.selectedFilter,
                    sort = uiState.sort,
                    viewMode = uiState.viewMode,
                    isPlaylistReorderMode = uiState.isPlaylistReorderMode,
                    multiSelectEnabled = multiSelectSupported,
                    onSetSort = onSetSort,
                    onEnterPlaylistReorder = onEnterPlaylistReorder,
                    onEnterSelectionMode = {
                        if (multiSelectSupported) {
                            onEnterSelectionMode()
                        } else {
                            Toast.makeText(
                                context,
                                context.getString(R.string.library_multi_select_unsupported),
                                Toast.LENGTH_SHORT,
                            ).show()
                        }
                    },
                    onToggleViewMode = onToggleViewMode,
                )
            }
            LibraryContentView(
                items = uiState.items,
                viewMode = uiState.viewMode,
                selectedFilter = uiState.selectedFilter,
                onItemClick = { item ->
                    if (uiState.isSelectionMode) {
                        onToggleSelection(item.id)
                    } else {
                        onItemClick(item)
                    }
                },
                onSongMoreClick = onSongMoreClick,
                onPlaylistMoreClick = onPlaylistMoreClick,
                onChannelMoreClick = onChannelMoreClick,
                onFindMusic = onFindMusic,
                isPlaylistReorderMode = uiState.isPlaylistReorderMode,
                onPlaylistOrderCommitted = onPlaylistOrderCommitted,
                isSelectionMode = uiState.isSelectionMode,
                selectedIds = uiState.selectedIds,
                modifier = Modifier.weight(1f),
            )
        }
    }

    if (showDeleteConfirm) {
        val isSongs = uiState.selectedFilter == LibraryFilterChip.SONGS
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            title = {
                Text(
                    stringResource(
                        if (isSongs) {
                            R.string.library_batch_delete_songs_title
                        } else {
                            R.string.library_batch_delete_playlists_title
                        },
                    ),
                )
            },
            text = {
                Text(
                    stringResource(
                        if (isSongs) {
                            R.string.library_batch_delete_songs_message
                        } else {
                            R.string.library_batch_delete_playlists_message
                        },
                        uiState.selectedCount,
                    ),
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showDeleteConfirm = false
                        onConfirmDeleteSelected()
                    },
                ) {
                    Text(stringResource(R.string.library_batch_delete))
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) {
                    Text(stringResource(R.string.library_cancel))
                }
            },
        )
    }
}
