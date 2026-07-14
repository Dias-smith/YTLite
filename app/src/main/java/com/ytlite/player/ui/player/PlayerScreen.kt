package com.ytlite.player.ui.player

import android.app.Activity
import android.app.Application
import android.graphics.Rect
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import com.ytlite.player.R
import com.ytlite.player.data.model.SubscriptionChannel
import com.ytlite.player.playback.GlobalPlaybackUiState
import com.ytlite.player.playback.GlobalPlaybackViewModel
import com.ytlite.player.playback.NowPlaying
import com.ytlite.player.playback.PlayQueueRepository
import com.ytlite.player.playback.PlaybackManager
import com.ytlite.player.ui.image.thumbnailRequest
import com.ytlite.player.ui.library.NewPlaylistDialog
import com.ytlite.player.ui.library.PlaylistPickerSheet
import com.ytlite.player.ui.library.PlaylistPickerViewModel
import com.ytlite.player.ui.theme.Orange40

private val PlayerDetailDarkColorScheme = darkColorScheme(
    primary = Orange40,
    onPrimary = Color.White,
    primaryContainer = Color(0xFFCC5500),
    onPrimaryContainer = Color(0xFFFFDBCC),
    background = Color(0xFF0D0D0D),
    onBackground = Color.White,
    surface = Color(0xFF0D0D0D),
    onSurface = Color.White,
    surfaceVariant = Color(0xFF2A2A2A),
    onSurfaceVariant = Color(0xFFB0B0B0),
)

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
    val attachInlineSurface by PlaybackManager.inlinePlayerSurfaceAttached.collectAsStateWithLifecycle()
    val isInPipMode by PlayerPipState.isInPictureInPictureMode.collectAsStateWithLifecycle()
    val playbackError by PlaybackManager.playbackError.collectAsStateWithLifecycle()
    val positionMs by PlaybackManager.positionMs.collectAsStateWithLifecycle()
    val durationMs by PlaybackManager.durationMs.collectAsStateWithLifecycle()
    val queueState by PlayQueueRepository.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val application = context.applicationContext as Application
    val activity = context as? Activity

    val playlistPickerViewModel: PlaylistPickerViewModel = viewModel(
        factory = PlaylistPickerViewModel.factory(application),
    )
    val playlistPickerState by playlistPickerViewModel.uiState.collectAsStateWithLifecycle()

    if (isInPipMode && uiState.playback != null && uiState.selectedStreamUrl != null) {
        val playback = requireNotNull(uiState.playback)
        val thumbnailUrl = NowPlaying.thumbnailUrlFor(playback.videoId)
        Box(modifier = modifier.fillMaxSize()) {
            PlayerSmartCanvas(
                player = sharedPlayer,
                thumbnailUrl = thumbnailUrl,
                uiState = uiState,
                globalPlaybackState = globalPlaybackState,
                attachInlineSurface = attachInlineSurface,
                viewModel = viewModel,
                globalPlaybackViewModel = globalPlaybackViewModel,
                layout = PlayerCanvasLayout.Pip,
                showPictureInPicture = false,
                onBack = { activity?.exitPlayerPictureInPicture() },
                onFullscreenClick = {
                    activity?.exitPlayerPictureInPicture()
                    viewModel.prepareVideoForFullscreen { surfaceMode ->
                        PlaybackManager.setInlinePlayerSurfaceAttached(false)
                        context.startActivity(
                            FullscreenPlayerActivity.createIntent(
                                context = context,
                                thumbnailUrl = thumbnailUrl,
                                surfaceMode = surfaceMode,
                            ),
                        )
                    }
                },
                onPictureInPictureClick = {},
                positionMs = positionMs,
                durationMs = durationMs,
                modifier = Modifier.fillMaxSize(),
            )
        }
    } else {
        Scaffold(
            modifier = modifier.fillMaxSize(),
        ) { innerPadding ->
            when {
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
                    val thumbnailUrl = NowPlaying.thumbnailUrlFor(playback.videoId)
                    val listState = rememberLazyListState()
                    val swipeToDismissState = rememberPlayerSwipeToDismissState(
                        listState = listState,
                        onDismiss = onBack,
                    )
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(innerPadding)
                            .playerSwipeToDismiss(swipeToDismissState, enabled = true),
                    ) {
                        if (uiState.selectedStreamUrl != null) {
                            PlayerSmartCanvas(
                                player = sharedPlayer,
                                thumbnailUrl = thumbnailUrl,
                                uiState = uiState,
                                globalPlaybackState = globalPlaybackState,
                                attachInlineSurface = attachInlineSurface,
                                viewModel = viewModel,
                                globalPlaybackViewModel = globalPlaybackViewModel,
                                layout = PlayerCanvasLayout.Inline,
                                showPictureInPicture = true,
                                onBack = onBack,
                                onFullscreenClick = {
                                    viewModel.prepareVideoForFullscreen { surfaceMode ->
                                        PlaybackManager.setInlinePlayerSurfaceAttached(false)
                                        context.startActivity(
                                            FullscreenPlayerActivity.createIntent(
                                                context = context,
                                                thumbnailUrl = thumbnailUrl,
                                                surfaceMode = surfaceMode,
                                            ),
                                        )
                                    }
                                },
                                onPictureInPictureClick = {
                                    activity?.enterPlayerPictureInPicture()
                                },
                                positionMs = positionMs,
                                durationMs = durationMs,
                                modifier = Modifier
                                    .playerSwipeToDismissHeader(swipeToDismissState, enabled = true)
                                    .onGloballyPositioned { coordinates ->
                                        val position = coordinates.positionInWindow()
                                        val size = coordinates.size
                                        PlayerPipState.sourceRectHint = Rect(
                                            position.x.toInt(),
                                            position.y.toInt(),
                                            (position.x + size.width).toInt(),
                                            (position.y + size.height).toInt(),
                                        )
                                    },
                            )
                            if (playbackError != null) {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
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
                            PlayerExtractingSurface(
                                thumbnailUrl = thumbnailUrl,
                                isExtracting = uiState.isExtracting,
                                onBack = onBack,
                            )
                        }

                        MaterialTheme(colorScheme = PlayerDetailDarkColorScheme) {
                            Column(
                                modifier = Modifier
                                    .weight(1f)
                                    .fillMaxWidth()
                                    .background(MaterialTheme.colorScheme.background),
                            ) {
                                LazyColumn(
                                    state = listState,
                                    modifier = Modifier.fillMaxSize(),
                                ) {
                                    item(key = "metadata") {
                                        PlayerMetadataPanel(
                                            playback = playback,
                                            showTitle = true,
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

                                    item(key = "transport") {
                                        PlayerDetailTransportBar(
                                            isPlaying = globalPlaybackState.isPlaying,
                                            shuffleEnabled = queueState.shuffleEnabled,
                                            repeatMode = queueState.repeatMode,
                                            onToggleShuffle = globalPlaybackViewModel::toggleShuffle,
                                            onCycleRepeatMode = globalPlaybackViewModel::cycleRepeatMode,
                                            onSkipPrevious = globalPlaybackViewModel::skipToPrevious,
                                            onTogglePlayPause = globalPlaybackViewModel::togglePlayPause,
                                            onSkipNext = globalPlaybackViewModel::skipToNext,
                                        )
                                    }

                                    stickyHeader(key = "list_header") {
                                        val songCount = when (uiState.selectedListTab) {
                                            PlayerListTab.UpNext -> queueState.items.size
                                            PlayerListTab.Recommend -> uiState.recommendedItems.size
                                            PlayerListTab.Lyrics -> 0
                                        }
                                        val canSaveList = when (uiState.selectedListTab) {
                                            PlayerListTab.UpNext -> queueState.items.isNotEmpty()
                                            PlayerListTab.Recommend -> uiState.recommendedItems.isNotEmpty()
                                            PlayerListTab.Lyrics -> false
                                        }
                                        PlayerDetailListHeader(
                                            selectedTab = uiState.selectedListTab,
                                            onTabSelected = viewModel::selectListTab,
                                            songCount = songCount,
                                            canSaveList = canSaveList,
                                            onSaveListClick = viewModel::showSaveCurrentListPlaylistPicker,
                                            modifier = Modifier
                                                .fillMaxWidth()
                                                .background(MaterialTheme.colorScheme.background),
                                        )
                                    }

                                    when (uiState.selectedListTab) {
                                        PlayerListTab.UpNext -> {
                                            items(
                                                items = queueState.items,
                                                key = { "queue:${it.videoId}" },
                                                contentType = { "queue" },
                                            ) { item ->
                                                PurifiedUpNextItem(
                                                    item = item.toVideoItem(),
                                                    isCurrentlyPlaying = globalPlaybackState.nowPlaying?.videoId == item.videoId,
                                                    isPlaying = globalPlaybackState.isPlaying,
                                                    onClick = { viewModel.onQueueItemClick(item) },
                                                )
                                            }
                                        }
                                        PlayerListTab.Lyrics -> {
                                            item(key = "lyrics_placeholder") {
                                                Text(
                                                    text = stringResource(R.string.player_lyrics_placeholder),
                                                    style = MaterialTheme.typography.bodyMedium,
                                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                                    modifier = Modifier.padding(24.dp),
                                                )
                                            }
                                        }
                                        PlayerListTab.Recommend -> {
                                            if (uiState.recommendLoading) {
                                                item(key = "recommend_loading") {
                                                    Box(
                                                        modifier = Modifier
                                                            .fillMaxWidth()
                                                            .padding(24.dp),
                                                        contentAlignment = Alignment.Center,
                                                    ) {
                                                        CircularProgressIndicator(
                                                            color = MaterialTheme.colorScheme.primary,
                                                        )
                                                    }
                                                }
                                            } else {
                                                items(
                                                    items = uiState.recommendedItems,
                                                    key = { "rec:${it.videoId}" },
                                                    contentType = { "recommend" },
                                                ) { item ->
                                                    PurifiedUpNextItem(
                                                        item = item,
                                                        isCurrentlyPlaying = globalPlaybackState.nowPlaying?.videoId == item.videoId,
                                                        isPlaying = globalPlaybackState.isPlaying,
                                                        onClick = { viewModel.onRecommendClick(item) },
                                                    )
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    val libraryVideo = viewModel.libraryVideo()
    val saveBatch = uiState.playlistSaveItems
    if (uiState.isPlaylistPickerVisible && (saveBatch != null || libraryVideo != null)) {
        PlaylistPickerSheet(
            playlists = playlistPickerState.playlists,
            trackCount = saveBatch?.size,
            subtitle = if (saveBatch == null) libraryVideo?.title else null,
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
private fun PlayerSmartCanvas(
    player: androidx.media3.common.Player?,
    thumbnailUrl: String,
    uiState: PlayerUiState,
    globalPlaybackState: GlobalPlaybackUiState,
    attachInlineSurface: Boolean,
    viewModel: PlayerViewModel,
    globalPlaybackViewModel: GlobalPlaybackViewModel,
    layout: PlayerCanvasLayout,
    showPictureInPicture: Boolean,
    onBack: () -> Unit,
    onFullscreenClick: () -> Unit,
    onPictureInPictureClick: () -> Unit,
    positionMs: Long,
    durationMs: Long,
    modifier: Modifier = Modifier,
) {
    SmartPlayerCanvas(
        player = player,
        thumbnailUrl = thumbnailUrl,
        surfaceMode = uiState.surfaceMode,
        positionMs = positionMs,
        durationMs = durationMs,
        isPlaying = globalPlaybackState.isPlaying,
        onSurfaceModeChange = viewModel::setSurfaceMode,
        attachPlayerSurface = attachInlineSurface,
        onFullscreenClick = onFullscreenClick,
        onPictureInPictureClick = onPictureInPictureClick,
        onSeek = globalPlaybackViewModel::seekTo,
        onTogglePlayPause = globalPlaybackViewModel::togglePlayPause,
        onSkipPrevious = globalPlaybackViewModel::skipToPrevious,
        onSkipNext = globalPlaybackViewModel::skipToNext,
        onBack = onBack,
        layout = layout,
        showPictureInPicture = showPictureInPicture,
        modifier = modifier,
    )
}

@Composable
private fun PlayerExtractingSurface(
    thumbnailUrl: String,
    isExtracting: Boolean,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    Box(
        modifier = modifier
            .fillMaxWidth()
            .aspectRatio(16f / 9f)
            .background(Color.Black),
    ) {
        AsyncImage(
            model = thumbnailRequest(context, thumbnailUrl),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        if (isExtracting) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.35f)),
                contentAlignment = Alignment.Center,
            ) {
                CircularProgressIndicator(
                    modifier = Modifier.size(40.dp),
                    color = Color.White,
                )
            }
        }
        IconButton(
            onClick = onBack,
            modifier = Modifier.align(Alignment.TopStart),
        ) {
            Icon(
                imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                contentDescription = stringResource(R.string.player_back),
                tint = Color.White,
            )
        }
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
