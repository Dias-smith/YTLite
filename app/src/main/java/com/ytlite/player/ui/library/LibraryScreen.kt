package com.ytlite.player.ui.library

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Help
import androidx.compose.material.icons.filled.Feedback
import androidx.compose.material.icons.filled.LocalMovies
import androidx.compose.material.icons.filled.Subscriptions
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material3.HorizontalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import android.app.Application
import com.ytlite.player.R
import com.ytlite.player.data.auth.UserSession

@Composable
fun LibraryScreen(
    onVideoClick: (String) -> Unit,
    onSwitchAccountClick: () -> Unit,
    onMenuItemClick: () -> Unit,
    onViewAllClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val application = LocalContext.current.applicationContext as Application
    val viewModel: LibraryViewModel = viewModel(factory = LibraryViewModel.factory(application))
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val session = uiState.session

    LaunchedEffect(session.ownerKey) {
        viewModel.refreshIfNeeded()
    }

    LazyColumn(modifier = modifier.fillMaxSize()) {
        item(key = "profile") {
            LibraryProfileHeader(
                session = session,
                onSwitchAccountClick = onSwitchAccountClick,
            )
        }

        item(key = "history_header") {
            LibrarySectionHeader(
                title = stringResource(R.string.library_history),
                onViewAllClick = onViewAllClick,
            )
        }

        item(key = "history_row") {
            LibraryHistoryRow(
                videos = uiState.history,
                onVideoClick = onVideoClick,
            )
        }

        item(key = "playlists_header") {
            LibrarySectionHeader(
                title = stringResource(R.string.library_playlists),
                onViewAllClick = onViewAllClick,
            )
        }

        item(key = "playlists_row") {
            LibraryPlaylistsRow(
                playlists = uiState.unifiedPlaylists,
                onPlaylistClick = { playlist ->
                    if (!playlist.isYoutube()) {
                        onMenuItemClick()
                    }
                },
                onCloneYoutubePlaylist = { playlist ->
                    viewModel.cloneYoutubePlaylistToLocal(playlist.playlistId)
                },
                modifier = Modifier.padding(bottom = 8.dp),
            )
        }

        item(key = "divider") {
            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
        }

        item(key = "menu_your_videos") {
            LibraryMenuItem(
                icon = Icons.Filled.VideoLibrary,
                label = stringResource(R.string.library_your_videos),
                onClick = onMenuItemClick,
            )
        }
        item(key = "menu_movies") {
            LibraryMenuItem(
                icon = Icons.Filled.LocalMovies,
                label = stringResource(R.string.library_movies),
                onClick = onMenuItemClick,
            )
        }
        item(key = "menu_help") {
            LibraryMenuItem(
                icon = Icons.AutoMirrored.Filled.Help,
                label = stringResource(R.string.library_help),
                onClick = onMenuItemClick,
            )
        }
        item(key = "menu_feedback") {
            LibraryMenuItem(
                icon = Icons.Filled.Feedback,
                label = stringResource(R.string.library_feedback),
                onClick = onMenuItemClick,
            )
        }
        item(key = "menu_premium") {
            LibraryMenuItem(
                icon = Icons.Filled.Subscriptions,
                label = stringResource(R.string.library_premium),
                onClick = onMenuItemClick,
                modifier = Modifier.padding(bottom = 16.dp),
            )
        }
    }
}
