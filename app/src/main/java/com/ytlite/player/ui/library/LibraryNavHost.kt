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
import com.ytlite.player.MainActivity
import com.ytlite.player.R
import com.ytlite.player.data.local.entity.PlaylistSystemType
import com.ytlite.player.data.model.LibraryItem
import com.ytlite.player.data.model.VideoItem
import com.ytlite.player.playback.QueueItem
import com.ytlite.player.ui.player.toQueueItem
import com.ytlite.player.ui.playlistaction.LocalPlaylistMoreClick
import com.ytlite.player.ui.playlistaction.PlaylistActionContext
import com.ytlite.player.ui.settings.SettingsScreen
import com.ytlite.player.ui.trackaction.LocalTrackMoreClick
import com.ytlite.player.ui.trackaction.TrackActionContext

@Composable
fun LibraryNavHost(
    onVideoClick: (VideoItem) -> Unit,
    onSignInClick: () -> Unit,
    onSignOutClick: () -> Unit,
    onNavigateHomeTab: () -> Unit,
    onPlayPlaylist: (List<QueueItem>, Int, String) -> Unit,
    onTogglePlayPause: () -> Unit,
    pendingAlbumName: String? = null,
    onPendingAlbumConsumed: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    val application = LocalContext.current.applicationContext as Application
    val activity = LocalContext.current as? MainActivity
    val viewModel: LibraryViewModel = viewModel(factory = LibraryViewModel.factory(application))
    val playlistPickerViewModel: PlaylistPickerViewModel = viewModel(
        factory = PlaylistPickerViewModel.factory(application),
    )
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val pickerState by playlistPickerViewModel.uiState.collectAsStateWithLifecycle()
    var destination by remember { mutableStateOf<LibraryDestination>(LibraryDestination.Home) }
    var showAccountSheet by remember { mutableStateOf(false) }
    var showNewPlaylistDialog by remember { mutableStateOf(false) }
    var showBatchPlaylistPicker by remember { mutableStateOf(false) }
    var showCreatePlaylistForBatch by remember { mutableStateOf(false) }
    val onTrackMoreClick = LocalTrackMoreClick.current
    val onPlaylistMoreClick = LocalPlaylistMoreClick.current
    val context = LocalContext.current

    LaunchedEffect(uiState.session?.ownerKey) {
        if (uiState.session != null) {
            viewModel.refreshIfNeeded()
        }
    }

    val session = uiState.session
    if (session == null) {
        return
    }

    LaunchedEffect(pendingAlbumName) {
        pendingAlbumName?.let { album ->
            destination = LibraryDestination.AlbumTracks(album)
            onPendingAlbumConsumed()
        }
    }

    AccountSwitcherSheet(
        session = session,
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

    if (showCreatePlaylistForBatch) {
        NewPlaylistDialog(
            onDismiss = { showCreatePlaylistForBatch = false },
            onConfirm = { name ->
                viewModel.createPlaylistAndAddSelected(name) {
                    showCreatePlaylistForBatch = false
                    showBatchPlaylistPicker = false
                }
            },
        )
    }

    if (showBatchPlaylistPicker) {
        PlaylistPickerSheet(
            playlists = pickerState.playlists,
            onDismiss = { showBatchPlaylistPicker = false },
            onPlaylistSelected = { playlistId ->
                viewModel.addSelectedSongsToPlaylist(playlistId) {
                    showBatchPlaylistPicker = false
                }
            },
            onCreatePlaylist = {
                showBatchPlaylistPicker = false
                showCreatePlaylistForBatch = true
            },
            trackCount = uiState.selectedCount,
        )
    }

    when (val current = destination) {
        LibraryDestination.Home -> {
            LibraryHomeScreen(
                uiState = uiState,
                onProfileClick = { showAccountSheet = true },
                onSettingsClick = { destination = LibraryDestination.Settings },
                onFilterSelected = viewModel::selectFilter,
                onSetSort = viewModel::setSort,
                onToggleViewMode = viewModel::toggleViewMode,
                onItemClick = { item ->
                    if (!uiState.isPlaylistReorderMode) {
                        when (item) {
                            is LibraryItem.Playlist -> {
                                if (item.systemType == PlaylistSystemType.HISTORY) {
                                    destination = LibraryDestination.History
                                } else {
                                    destination = LibraryDestination.Playlist(
                                        playlistId = item.playlistId,
                                        systemType = item.systemType,
                                    )
                                }
                            }
                            is LibraryItem.Album -> {
                                destination = LibraryDestination.AlbumTracks(item.albumName)
                            }
                            is LibraryItem.Song -> {
                                val songs = uiState.items.filterIsInstance<LibraryItem.Song>()
                                val queue = songs.map { it.toQueueItem() }
                                val startIndex = queue.indexOfFirst { it.videoId == item.videoId }
                                    .coerceAtLeast(0)
                                if (queue.isNotEmpty()) {
                                    onPlayPlaylist(queue, startIndex, "library:songs")
                                }
                            }
                            is LibraryItem.Artist -> Unit
                        }
                    }
                },
                onToggleSelection = viewModel::toggleSelection,
                onEnterSelectionMode = viewModel::enterSelectionMode,
                onExitSelectionMode = viewModel::exitSelectionMode,
                onSelectAll = viewModel::selectAllSelectable,
                onDeselectAll = viewModel::deselectAll,
                onSongMoreClick = { song ->
                    onTrackMoreClick(TrackActionContext.fromLibraryItemSong(song))
                },
                onPlaylistMoreClick = { playlist ->
                    onPlaylistMoreClick(
                        PlaylistActionContext.fromLibraryItem(playlist, session.ownerKey),
                    )
                },
                onFindMusic = onNavigateHomeTab,
                onNewPlaylist = { showNewPlaylistDialog = true },
                onEnterPlaylistReorder = viewModel::enterPlaylistReorderMode,
                onExitPlaylistReorder = viewModel::exitPlaylistReorderMode,
                onPlaylistOrderCommitted = viewModel::commitPlaylistOrder,
                onBatchAddToPlaylist = { showBatchPlaylistPicker = true },
                onConfirmDeleteSelected = {
                    viewModel.deleteSelected { skipped ->
                        if (skipped) {
                            viewModel.showSnackbar(
                                context.getString(R.string.library_batch_delete_skipped),
                            )
                        }
                    }
                },
                onSnackbarConsumed = viewModel::clearSnackbar,
                modifier = modifier,
            )
        }
        LibraryDestination.History -> {
            HistoryScreen(
                ownerKey = session.ownerKey,
                onBack = { destination = LibraryDestination.Home },
                onPlayPlaylist = onPlayPlaylist,
                onSongMoreClick = { video, playlistId, source ->
                    onTrackMoreClick(
                        TrackActionContext.fromLibraryVideo(video, playlistId, source),
                    )
                },
                modifier = modifier,
            )
        }
        is LibraryDestination.Playlist -> {
            PlaylistDetailScreen(
                playlistId = current.playlistId,
                systemType = current.systemType,
                ownerKey = session.ownerKey,
                onBack = { destination = LibraryDestination.Home },
                onVideoClick = onVideoClick,
                onCloneYoutubePlaylist = { viewModel.cloneYoutubePlaylistToLocal(current.playlistId) },
                onSongMoreClick = { track, playlistId, source ->
                    onTrackMoreClick(
                        TrackActionContext.fromPlaylistTrack(track, playlistId, source),
                    )
                },
                onPlaylistMoreClick = { context ->
                    onPlaylistMoreClick(context)
                },
                onPlayPlaylist = onPlayPlaylist,
                onTogglePlayPause = onTogglePlayPause,
                modifier = modifier,
            )
        }
        is LibraryDestination.AlbumTracks -> {
            AlbumTracksScreen(
                albumName = current.albumName,
                ownerKey = session.ownerKey,
                onBack = { destination = LibraryDestination.Home },
                onPlayPlaylist = onPlayPlaylist,
                modifier = modifier,
            )
        }
        LibraryDestination.Settings -> {
            SettingsScreen(
                onBack = { destination = LibraryDestination.Home },
                onLanguageChanged = { activity?.recreate() },
                modifier = modifier,
            )
        }
    }
}
