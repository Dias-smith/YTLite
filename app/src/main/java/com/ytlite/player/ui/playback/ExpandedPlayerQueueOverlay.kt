package com.ytlite.player.ui.playback

import android.app.Application
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cast
import androidx.compose.material.icons.filled.ClosedCaption
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import com.ytlite.player.R
import com.ytlite.player.playback.CastShareHelper
import com.ytlite.player.playback.ExpandedPlayerUiState
import com.ytlite.player.playback.GlobalPlaybackUiState
import com.ytlite.player.playback.GlobalPlaybackViewModel
import com.ytlite.player.playback.QueueItem
import com.ytlite.player.ui.player.FullscreenPlayerActivity
import com.ytlite.player.ui.player.PlaybackFormatSelector

@Composable
fun ExpandedPlayerQueueOverlay(
    state: GlobalPlaybackUiState,
    expandedState: ExpandedPlayerUiState,
    viewModel: GlobalPlaybackViewModel,
    modifier: Modifier = Modifier,
) {
    if (!state.isQueueExpanded || state.nowPlaying == null) return

    val nowPlaying = state.nowPlaying
    val context = LocalContext.current
    val application = context.applicationContext as Application
    val snackbarHostState = remember { SnackbarHostState() }
    var actionItem by remember { mutableStateOf<QueueItem?>(null) }

    val signInRequired = stringResource(R.string.player_sign_in_required)
    val noCaptions = stringResource(R.string.player_no_captions)
    val captionFailed = stringResource(R.string.player_caption_load_failed)

    LaunchedEffect(expandedState.pendingSnackbar) {
        when (expandedState.pendingSnackbar) {
            "sign_in_required" -> snackbarHostState.showSnackbar(signInRequired)
            "no_captions" -> snackbarHostState.showSnackbar(noCaptions)
            "caption_load_failed" -> snackbarHostState.showSnackbar(captionFailed)
        }
        if (expandedState.pendingSnackbar != null) {
            viewModel.clearSnackbar()
        }
    }

    BackHandler { viewModel.setQueueExpanded(false) }

    Box(
        modifier = modifier
            .fillMaxSize()
            .zIndex(10f)
            .background(Color.Black),
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            RowTopBar(
                subtitlesEnabled = expandedState.subtitlesEnabled,
                onCollapse = { viewModel.setQueueExpanded(false) },
                onCast = {
                    when (val action = CastShareHelper.openCastOrShare(context, nowPlaying.videoId)) {
                        is CastShareHelper.CastAction.Launch -> context.startActivity(action.intent)
                        is CastShareHelper.CastAction.Shared -> Unit
                    }
                },
                onCc = { viewModel.toggleSubtitles(application) },
                onSettings = { viewModel.showSettingsSheet(true) },
            )

            ExpandedPlayerSurface(
                nowPlaying = nowPlaying,
                isPlaying = state.isPlaying,
                positionMs = state.positionMs,
                durationMs = state.durationMs,
                onSeek = viewModel::seekTo,
                onTogglePlayPause = viewModel::togglePlayPause,
                onSkipPrevious = viewModel::skipToPrevious,
                onSkipNext = viewModel::skipToNext,
                onFullscreen = {
                    context.startActivity(
                        FullscreenPlayerActivity.createIntent(
                            context = context,
                            thumbnailUrl = nowPlaying.thumbnailUrl,
                        ),
                    )
                },
                modifier = Modifier.fillMaxWidth(),
            )

            HorizontalDivider(color = Color(0xFF333333))

            QueueHeader(
                currentTitle = nowPlaying.title,
                repeatMode = state.queueState.repeatMode,
                shuffleEnabled = state.queueState.shuffleEnabled,
                onCycleRepeat = viewModel::cycleRepeatMode,
                onToggleShuffle = viewModel::toggleShuffle,
                onMore = { viewModel.showSettingsSheet(true) },
                onClose = { viewModel.setQueueExpanded(false) },
            )

            LazyColumn(modifier = Modifier.fillMaxSize()) {
                itemsIndexed(
                    items = state.queueState.items,
                    key = { _, item -> item.videoId },
                ) { index, item ->
                    val isCurrent = item.videoId == nowPlaying.videoId
                    QueueListItem(
                        item = item,
                        isCurrent = isCurrent,
                        index = index,
                        itemCount = state.queueState.items.size,
                        onClick = {
                            viewModel.playQueueItem(item)
                        },
                        onMoreClick = { actionItem = item },
                        onDrag = viewModel::reorderQueue,
                    )
                    if (isCurrent) {
                        LikeDislikeRow(
                            isLiked = expandedState.isLiked,
                            isDisliked = expandedState.isDisliked,
                            onLike = { viewModel.toggleLike(application) },
                            onDislike = { viewModel.toggleDislike(application) },
                        )
                    }
                }
            }
        }

        SnackbarHost(
            hostState = snackbarHostState,
            modifier = Modifier.align(Alignment.BottomCenter),
        )
    }

    PlaybackSettingsSheet(
        visible = expandedState.showSettingsSheet,
        currentSpeed = expandedState.playbackSpeed,
        formats = PlaybackFormatSelector.listVideoFormats(expandedState.currentFormats),
        selectedItag = expandedState.preferredItag,
        onDismiss = { viewModel.showSettingsSheet(false) },
        onSpeedSelected = viewModel::setPlaybackSpeed,
        onFormatSelected = viewModel::selectQualityFormat,
    )

    CaptionLanguageSheet(
        visible = expandedState.showCaptionSheet,
        tracks = expandedState.captionTracks,
        selected = expandedState.selectedCaption,
        onDismiss = { viewModel.showCaptionSheet(false) },
        onTrackSelected = { track -> viewModel.selectCaptionTrack(application, track) },
    )

    actionItem?.let { item ->
        QueueItemActionSheet(
            context = item.toSongActionContext(),
            showRemoveFromQueue = true,
            onDismiss = { actionItem = null },
            onRemoveFromQueue = { viewModel.removeFromQueue(item.videoId) },
        )
    }
}

@Composable
private fun RowTopBar(
    subtitlesEnabled: Boolean,
    onCollapse: () -> Unit,
    onCast: () -> Unit,
    onCc: () -> Unit,
    onSettings: () -> Unit,
) {
    androidx.compose.foundation.layout.Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 4.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = onCollapse) {
            Icon(
                imageVector = Icons.Filled.KeyboardArrowDown,
                contentDescription = stringResource(R.string.player_close_queue),
                tint = Color.White,
            )
        }
        Box(modifier = Modifier.weight(1f))
        IconButton(onClick = onCast) {
            Icon(
                imageVector = Icons.Filled.Cast,
                contentDescription = stringResource(R.string.player_cast),
                tint = Color.White,
            )
        }
        IconButton(onClick = onCc) {
            Icon(
                imageVector = Icons.Filled.ClosedCaption,
                contentDescription = stringResource(R.string.player_cc),
                tint = if (subtitlesEnabled) Color(0xFFFF0000) else Color.White,
            )
        }
        IconButton(onClick = onSettings) {
            Icon(
                imageVector = Icons.Filled.Settings,
                contentDescription = stringResource(R.string.player_settings),
                tint = Color.White,
            )
        }
    }
}
