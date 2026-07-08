package com.ytlite.player.ui.library

import android.app.Application
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.ytlite.player.data.model.LibraryItem

@Composable
fun LibraryNavHost(
    onVideoClick: (String) -> Unit,
    onSignInClick: () -> Unit,
    onSignOutClick: () -> Unit,
    onNavigateHomeTab: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val application = LocalContext.current.applicationContext as Application
    val viewModel: LibraryViewModel = viewModel(factory = LibraryViewModel.factory(application))
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    var destination by remember { mutableStateOf<LibraryDestination>(LibraryDestination.Home) }
    var showAccountSheet by remember { mutableStateOf(false) }
    var showNewPlaylistDialog by remember { mutableStateOf(false) }
    var songActionContext by remember { mutableStateOf<SongActionContext?>(null) }

    LaunchedEffect(uiState.session.ownerKey) {
        viewModel.refreshIfNeeded()
    }

    AccountSwitcherSheet(
        session = uiState.session,
        visible = showAccountSheet,
        onDismiss = { showAccountSheet = false },
        onAddAccountClick = onSignInClick,
        onSignOutClick = onSignOutClick,
    )

    if (showNewPlaylistDialog) {
        NewPlaylistDialog(
            onDismiss = { showNewPlaylistDialog = false },
            onConfirm = { name ->
                viewModel.createPlaylist(name)
                showNewPlaylistDialog = false
            },
        )
    }

    songActionContext?.let { context ->
        SongActionBottomSheet(
            context = context,
            onDismiss = { songActionContext = null },
            onVideoClick = onVideoClick,
        )
    }

    when (val current = destination) {
        LibraryDestination.Home -> {
            LibraryHomeScreen(
                uiState = uiState,
                onHistoryClick = { destination = LibraryDestination.History },
                onProfileClick = { showAccountSheet = true },
                onFilterSelected = viewModel::selectFilter,
                onClearFilter = viewModel::clearFilter,
                onSortClick = viewModel::toggleSort,
                onToggleViewMode = viewModel::toggleViewMode,
                onItemClick = { item ->
                    when (item) {
                        is LibraryItem.Playlist -> {
                            destination = LibraryDestination.Playlist(item.playlistId)
                        }
                        is LibraryItem.Song -> onVideoClick(item.videoId)
                        is LibraryItem.Artist -> Unit
                    }
                },
                onFindMusic = onNavigateHomeTab,
                onNewPlaylist = { showNewPlaylistDialog = true },
                modifier = modifier,
            )
        }
        LibraryDestination.History -> {
            HistoryScreen(
                ownerKey = uiState.session.ownerKey,
                onBack = { destination = LibraryDestination.Home },
                onVideoClick = onVideoClick,
                onSongMoreClick = { video, playlistId, source ->
                    songActionContext = SongActionContext(
                        videoId = video.videoId,
                        title = video.title,
                        channelName = video.channelName,
                        thumbnailUrl = video.thumbnailUrl,
                        playlistId = playlistId,
                        playlistSource = source,
                    )
                },
                modifier = modifier,
            )
        }
        is LibraryDestination.Playlist -> {
            PlaylistDetailScreen(
                playlistId = current.playlistId,
                ownerKey = uiState.session.ownerKey,
                onBack = { destination = LibraryDestination.Home },
                onVideoClick = onVideoClick,
                onCloneYoutubePlaylist = { viewModel.cloneYoutubePlaylistToLocal(current.playlistId) },
                onSongMoreClick = { track, playlistId, source ->
                    songActionContext = SongActionContext(
                        videoId = track.trackId,
                        title = track.title,
                        channelName = track.primaryArtistName.orEmpty(),
                        thumbnailUrl = track.thumbnailUrl,
                        playlistId = playlistId,
                        playlistSource = source,
                    )
                },
                modifier = modifier,
            )
        }
    }
}

data class SongActionContext(
    val videoId: String,
    val title: String,
    val channelName: String,
    val thumbnailUrl: String,
    val playlistId: String?,
    val playlistSource: com.ytlite.player.data.model.DataSource,
)
