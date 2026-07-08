package com.ytlite.player.ui.player

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DragHandle
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.ytlite.player.R
import com.ytlite.player.playback.GlobalPlaybackUiState
import com.ytlite.player.playback.NowPlaying
import com.ytlite.player.playback.PlayQueueState
import com.ytlite.player.playback.QueueItem

private val MiniPlayerBackground = Color(0xFF212121)
private val ProgressBlue = Color(0xFF3EA6FF)

@Composable
fun PlayerMiniBar(
    state: GlobalPlaybackUiState,
    player: androidx.media3.common.Player?,
    onOpenQueue: () -> Unit,
    onTogglePlayPause: () -> Unit,
    onSkipNext: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val nowPlaying = state.nowPlaying ?: return
    val nextTitle = state.queueState.nextItem?.title
    val progress = if (state.durationMs > 0) {
        (state.positionMs.toFloat() / state.durationMs.toFloat()).coerceIn(0f, 1f)
    } else {
        0f
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(MiniPlayerBackground),
    ) {
        LinearProgressIndicator(
            progress = { progress },
            modifier = Modifier
                .fillMaxWidth()
                .height(2.dp),
            color = ProgressBlue,
            trackColor = Color(0xFF424242),
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(56.dp)
                .padding(end = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(
                modifier = Modifier
                    .weight(1f)
                    .clickableNoRipple(onOpenQueue),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                MiniPlayerSurface(
                    player = player,
                    modifier = Modifier.size(width = 80.dp, height = 56.dp),
                )
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .padding(horizontal = 12.dp),
                    verticalArrangement = Arrangement.Center,
                ) {
                    Text(
                        text = nowPlaying.title,
                        style = MaterialTheme.typography.bodyMedium,
                        color = Color.White,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        text = if (nextTitle != null) {
                            stringResource(R.string.player_next_label, nextTitle)
                        } else {
                            nowPlaying.channelName
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = Color(0xFFAAAAAA),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            IconButton(onClick = onTogglePlayPause) {
                Icon(
                    imageVector = if (state.isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                    contentDescription = null,
                    tint = Color(0xFFAAAAAA),
                )
            }
            IconButton(onClick = onSkipNext) {
                Icon(
                    imageVector = Icons.Filled.SkipNext,
                    contentDescription = null,
                    tint = Color(0xFFAAAAAA),
                )
            }
            IconButton(onClick = onOpenQueue) {
                Icon(
                    imageVector = Icons.Filled.KeyboardArrowUp,
                    contentDescription = stringResource(R.string.player_open_queue),
                    tint = Color(0xFFAAAAAA),
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SlidingPlayQueueSheet(
    visible: Boolean,
    queueState: PlayQueueState,
    nowPlaying: NowPlaying?,
    onDismiss: () -> Unit,
    onItemClick: (Int, QueueItem) -> Unit,
    onReorder: (Int, Int) -> Unit,
) {
    if (!visible) return
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)
    var dragFromIndex by remember { mutableIntStateOf(-1) }
    var dragToIndex by remember { mutableIntStateOf(-1) }
    var dragOffsetY by remember { mutableFloatStateOf(0f) }
    var localItems by remember(queueState.items) { mutableStateOf(queueState.items) }
    val itemHeightPx = with(LocalDensity.current) { 56.dp.toPx() }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        modifier = Modifier.fillMaxSize(),
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            Text(
                text = stringResource(R.string.player_queue_title),
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
            HorizontalDivider()
            LazyColumn(modifier = Modifier.fillMaxSize()) {
                itemsIndexed(localItems, key = { _, item -> item.videoId }) { index, item ->
                    val isCurrent = item.videoId == nowPlaying?.videoId
                    val isDragging = index == dragFromIndex
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(
                                when {
                                    isDragging -> MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.5f)
                                    isCurrent -> MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.35f)
                                    else -> Color.Transparent
                                },
                            )
                            .clickableNoRipple { onItemClick(index, item) }
                            .pointerInput(item.videoId, localItems.size) {
                                detectDragGesturesAfterLongPress(
                                    onDragStart = {
                                        dragFromIndex = index
                                        dragToIndex = index
                                        dragOffsetY = 0f
                                    },
                                    onDrag = { change, dragAmount ->
                                        change.consume()
                                        dragOffsetY += dragAmount.y
                                        val delta = (dragOffsetY / itemHeightPx).toInt()
                                        dragToIndex = (dragFromIndex + delta)
                                            .coerceIn(0, localItems.lastIndex)
                                    },
                                    onDragEnd = {
                                        if (dragFromIndex >= 0 && dragToIndex >= 0 && dragFromIndex != dragToIndex) {
                                            val mutable = localItems.toMutableList()
                                            val moved = mutable.removeAt(dragFromIndex)
                                            mutable.add(dragToIndex, moved)
                                            localItems = mutable
                                            onReorder(dragFromIndex, dragToIndex)
                                        }
                                        dragFromIndex = -1
                                        dragToIndex = -1
                                        dragOffsetY = 0f
                                    },
                                    onDragCancel = {
                                        dragFromIndex = -1
                                        dragToIndex = -1
                                        dragOffsetY = 0f
                                    },
                                )
                            }
                            .padding(horizontal = 16.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = item.title,
                                style = MaterialTheme.typography.bodyMedium,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                            Text(
                                text = item.channelName,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                        Icon(
                            imageVector = Icons.Filled.DragHandle,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun Modifier.clickableNoRipple(onClick: () -> Unit): Modifier {
    val interactionSource = remember { MutableInteractionSource() }
    return clickable(
        interactionSource = interactionSource,
        indication = null,
        onClick = onClick,
    )
}
