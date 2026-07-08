package com.ytlite.player.ui.playback

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.ytlite.player.R
import com.ytlite.player.playback.GlobalPlaybackUiState
import com.ytlite.player.ui.player.MiniPlayerSurface

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

@Composable
internal fun Modifier.clickableNoRipple(onClick: () -> Unit): Modifier {
    val interactionSource = remember { MutableInteractionSource() }
    return clickable(
        interactionSource = interactionSource,
        indication = null,
        onClick = onClick,
    )
}
