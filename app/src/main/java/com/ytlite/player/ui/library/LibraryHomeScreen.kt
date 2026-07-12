package com.ytlite.player.ui.library

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.ytlite.player.R
import com.ytlite.player.data.model.LibraryFilterChip
import com.ytlite.player.data.model.LibraryItem

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryHomeScreen(
    uiState: LibraryUiState,
    onProfileClick: () -> Unit,
    onFilterSelected: (LibraryFilterChip) -> Unit,
    onToggleViewMode: () -> Unit,
    onItemClick: (LibraryItem) -> Unit,
    onSongMoreClick: (LibraryItem.Song) -> Unit,
    onPlaylistMoreClick: (LibraryItem.Playlist) -> Unit,
    onFindMusic: () -> Unit,
    onNewPlaylist: () -> Unit,
    onEnterPlaylistReorder: () -> Unit = {},
    onExitPlaylistReorder: () -> Unit = {},
    onPlaylistReorder: ((from: Int, to: Int) -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text(text = stringResource(R.string.nav_library)) },
                actions = {
                    IconButton(onClick = onProfileClick) {
                        Icon(
                            imageVector = Icons.Default.AccountCircle,
                            contentDescription = stringResource(R.string.account_switcher_title),
                        )
                    }
                },
            )
        },
        floatingActionButton = {
            FloatingActionButton(onClick = onNewPlaylist) {
                Text(text = stringResource(R.string.library_new_fab))
            }
        },
    ) { innerPadding ->
        androidx.compose.foundation.layout.Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
        ) {
            LibraryFilterChips(
                visibleChips = uiState.visibleChips,
                selectedFilter = uiState.selectedFilter,
                onChipSelected = onFilterSelected,
                viewMode = uiState.viewMode,
                onToggleViewMode = onToggleViewMode,
                isPlaylistReorderMode = uiState.isPlaylistReorderMode,
                onEnterPlaylistReorder = onEnterPlaylistReorder,
                onExitPlaylistReorder = onExitPlaylistReorder,
            )
            LibraryContentView(
                items = uiState.items,
                viewMode = uiState.viewMode,
                selectedFilter = uiState.selectedFilter,
                onItemClick = onItemClick,
                onSongMoreClick = onSongMoreClick,
                onPlaylistMoreClick = onPlaylistMoreClick,
                onFindMusic = onFindMusic,
                isPlaylistReorderMode = uiState.isPlaylistReorderMode,
                onPlaylistReorder = onPlaylistReorder,
                modifier = Modifier.weight(1f),
            )
        }
    }
}
