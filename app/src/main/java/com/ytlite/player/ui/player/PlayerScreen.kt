package com.ytlite.player.ui.player

import android.app.Activity
import android.app.Application
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
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
import com.ytlite.player.data.model.SubscriptionChannel
import com.ytlite.player.playback.GlobalPlaybackUiState
import com.ytlite.player.playback.GlobalPlaybackViewModel
import com.ytlite.player.playback.PlaybackManager
import com.ytlite.player.ui.library.NewPlaylistDialog
import com.ytlite.player.ui.library.PlaylistPickerSheet
import com.ytlite.player.ui.library.PlaylistPickerViewModel

@Composable
fun PlayerScreen(
    onBack: () -> Unit,
    onChannelClick: (SubscriptionChannel) -> Unit,
    viewModel: PlayerViewModel,
    globalPlaybackViewModel: GlobalPlaybackViewModel,
    globalPlaybackState: GlobalPlaybackUiState,
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val expandedState by globalPlaybackViewModel.expandedUiState.collectAsStateWithLifecycle()
    val sharedPlayer by PlaybackManager.playerState.collectAsStateWithLifecycle()
    val playbackError by PlaybackManager.playbackError.collectAsStateWithLifecycle()
    val positionMs by PlaybackManager.positionMs.collectAsStateWithLifecycle()
    val durationMs by PlaybackManager.durationMs.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val application = context.applicationContext as Application
    val activity = context as? Activity

    val playlistPickerViewModel: PlaylistPickerViewModel = viewModel(
        factory = PlaylistPickerViewModel.factory(application),
    )
    val playlistPickerState by playlistPickerViewModel.uiState.collectAsStateWithLifecycle()

    Scaffold(
        modifier = modifier.fillMaxSize(),
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
                                    isPlaying = globalPlaybackState.isPlaying,
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
                                    onPictureInPictureClick = {
                                        activity?.enterPlayerPictureInPicture()
                                    },
                                    onSeek = globalPlaybackViewModel::seekTo,
                                    onTogglePlayPause = globalPlaybackViewModel::togglePlayPause,
                                    onSkipPrevious = globalPlaybackViewModel::skipToPrevious,
                                    onSkipNext = globalPlaybackViewModel::skipToNext,
                                    onBack = onBack,
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
                            isLiked = expandedState.isLiked,
                            isDisliked = expandedState.isDisliked,
                            onLike = { globalPlaybackViewModel.toggleLike(application) },
                            onDislike = { globalPlaybackViewModel.toggleDislike(application) },
                            onShare = { shareVideo(context, playback.videoId) },
                            onSaveToPlaylist = viewModel::showPlaylistPicker,
                            onChannelClick = {
                                if (playback.channelId.isNotBlank()) {
                                    onChannelClick(
                                        SubscriptionChannel(
                                            channelId = playback.channelId,
                                            title = playback.channelName,
                                            handle = null,
                                            avatarUrl = "",
                                            subscriberCountText = null,
                                            description = null,
                                        ),
                                    )
                                }
                            },
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
