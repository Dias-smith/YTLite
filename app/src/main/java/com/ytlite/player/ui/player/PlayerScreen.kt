package com.ytlite.player.ui.player

import android.app.Application
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.ytlite.player.R
import com.ytlite.player.playback.GlobalPlaybackUiState
import com.ytlite.player.playback.GlobalPlaybackViewModel
import com.ytlite.player.playback.PlaybackManager
import com.ytlite.player.ui.library.NewPlaylistDialog
import com.ytlite.player.ui.library.PlaylistPickerSheet
import com.ytlite.player.ui.library.PlaylistPickerViewModel
import com.ytlite.player.ui.playback.PlayerMiniBar

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlayerScreen(
    onBack: () -> Unit,
    viewModel: PlayerViewModel,
    globalPlaybackViewModel: GlobalPlaybackViewModel,
    globalPlaybackState: GlobalPlaybackUiState,
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val sharedPlayer by PlaybackManager.playerState.collectAsStateWithLifecycle()
    val playbackError by PlaybackManager.playbackError.collectAsStateWithLifecycle()
    val positionMs by PlaybackManager.positionMs.collectAsStateWithLifecycle()
    val durationMs by PlaybackManager.durationMs.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val application = context.applicationContext as Application

    val playlistPickerViewModel: PlaylistPickerViewModel = viewModel(
        factory = PlaylistPickerViewModel.factory(application),
    )
    val playlistPickerState by playlistPickerViewModel.uiState.collectAsStateWithLifecycle()

    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.player_back),
                        )
                    }
                },
            )
        },
        bottomBar = {
            if (globalPlaybackState.nowPlaying != null) {
                PlayerMiniBar(
                    state = globalPlaybackState,
                    player = sharedPlayer,
                    onOpenQueue = { globalPlaybackViewModel.setQueueExpanded(true) },
                    onTogglePlayPause = globalPlaybackViewModel::togglePlayPause,
                    onSkipNext = globalPlaybackViewModel::skipToNext,
                )
            }
        },
    ) { innerPadding ->
        when {
            uiState.isLoading -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }
            uiState.errorMessage != null && uiState.playback == null -> {
                ErrorContent(
                    message = uiState.errorMessage.orEmpty(),
                    onRetry = { viewModel.loadPlayback() },
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding),
                )
            }
            uiState.playback != null -> {
                val playback = requireNotNull(uiState.playback)
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding),
                ) {
                    item(key = "player_surface") {
                        Column {
                            if (uiState.selectedStreamUrl != null) {
                                SmartPlayerCanvas(
                                    player = sharedPlayer,
                                    thumbnailUrl = playback.let {
                                        com.ytlite.player.playback.NowPlaying.thumbnailUrlFor(it.videoId)
                                    },
                                    surfaceMode = uiState.surfaceMode,
                                    positionMs = positionMs,
                                    durationMs = durationMs,
                                    onSurfaceModeChange = viewModel::setSurfaceMode,
                                    onFullscreenClick = {
                                        context.startActivity(
                                            FullscreenPlayerActivity.createIntent(
                                                context = context,
                                                thumbnailUrl = com.ytlite.player.playback.NowPlaying
                                                    .thumbnailUrlFor(playback.videoId),
                                            ),
                                        )
                                    },
                                    onCcClick = { },
                                    onSettingsClick = { },
                                )
                                if (playbackError != null) {
                                    Box(
                                        modifier = Modifier
                                            .fillMaxSize()
                                            .padding(16.dp),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                            Text(
                                                text = stringResource(R.string.player_playback_failed),
                                                style = MaterialTheme.typography.titleSmall,
                                            )
                                            Text(
                                                text = playbackError.orEmpty(),
                                                style = MaterialTheme.typography.bodySmall,
                                            )
                                            Button(onClick = { viewModel.loadPlayback() }) {
                                                Text(text = stringResource(R.string.home_retry))
                                            }
                                        }
                                    }
                                }
                            } else {
                                Box(
                                    modifier = Modifier.fillMaxSize(),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    CircularProgressIndicator()
                                }
                            }
                        }
                    }

                    item(key = "metadata") {
                        PlayerMetadataPanel(
                            playback = playback,
                            isDescriptionExpanded = uiState.isDescriptionExpanded,
                            onToggleDescription = viewModel::toggleDescription,
                            onShare = { shareVideo(context, playback.videoId) },
                            onSaveToPlaylist = viewModel::showPlaylistPicker,
                        )
                    }

                    item(key = "up_next_header") {
                        PurifiedUpNextHeader()
                    }

                    if (uiState.upNextLoading) {
                        item(key = "up_next_loading") {
                            Box(
                                modifier = Modifier
                                    .fillMaxSize()
                                    .padding(24.dp),
                                contentAlignment = Alignment.Center,
                            ) {
                                CircularProgressIndicator()
                            }
                        }
                    } else {
                        items(
                            items = uiState.upNextItems,
                            key = { it.videoId },
                            contentType = { "video" },
                        ) { item ->
                            PurifiedUpNextItem(
                                item = item,
                                onClick = { viewModel.onUpNextClick(item) },
                            )
                        }
                    }
                }
            }
        }
    }

    val libraryVideo = viewModel.libraryVideo()
    if (uiState.isPlaylistPickerVisible && libraryVideo != null) {
        PlaylistPickerSheet(
            video = libraryVideo,
            playlists = playlistPickerState.playlists,
            onDismiss = viewModel::dismissPlaylistPicker,
            onPlaylistSelected = viewModel::saveToPlaylist,
            onCreatePlaylist = viewModel::showNewPlaylistDialog,
        )
    }

    if (uiState.showNewPlaylistDialog) {
        NewPlaylistDialog(
            onDismiss = viewModel::dismissNewPlaylistDialog,
            onConfirm = viewModel::createPlaylistAndSave,
        )
    }
}

@Composable
private fun ErrorContent(
    message: String,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(modifier = modifier, contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = stringResource(R.string.player_error),
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                text = message,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Button(onClick = onRetry) {
                Text(text = stringResource(R.string.home_retry))
            }
        }
    }
}
