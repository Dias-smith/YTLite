package com.ytlite.player.ui.player

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.outlined.Repeat
import androidx.compose.material.icons.outlined.RepeatOne
import androidx.compose.material.icons.outlined.Shuffle
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.ytlite.player.R
import com.ytlite.player.playback.QueueRepeatMode

@Composable
fun PlayerDetailTransportBar(
    isPlaying: Boolean,
    shuffleEnabled: Boolean,
    repeatMode: QueueRepeatMode,
    onToggleShuffle: () -> Unit,
    onCycleRepeatMode: () -> Unit,
    onSkipPrevious: () -> Unit,
    onTogglePlayPause: () -> Unit,
    onSkipNext: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val accent = MaterialTheme.colorScheme.primary
    val idle = MaterialTheme.colorScheme.onSurface
    val muted = MaterialTheme.colorScheme.onSurfaceVariant

    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = onToggleShuffle) {
            Icon(
                imageVector = Icons.Outlined.Shuffle,
                contentDescription = stringResource(
                    if (shuffleEnabled) {
                        R.string.player_mode_shuffle
                    } else {
                        R.string.player_mode_sequential
                    },
                ),
                tint = if (shuffleEnabled) accent else idle,
            )
        }
        IconButton(onClick = onSkipPrevious) {
            Icon(
                imageVector = Icons.Filled.SkipPrevious,
                contentDescription = stringResource(R.string.player_skip_previous),
                tint = idle,
                modifier = Modifier.size(36.dp),
            )
        }
        Surface(
            onClick = onTogglePlayPause,
            shape = CircleShape,
            color = MaterialTheme.colorScheme.onSurface,
            contentColor = MaterialTheme.colorScheme.surface,
            modifier = Modifier.size(64.dp),
        ) {
            Icon(
                imageVector = if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                contentDescription = stringResource(
                    if (isPlaying) R.string.player_pause else R.string.player_play,
                ),
                modifier = Modifier
                    .size(64.dp)
                    .padding(16.dp),
            )
        }
        IconButton(onClick = onSkipNext) {
            Icon(
                imageVector = Icons.Filled.SkipNext,
                contentDescription = stringResource(R.string.player_skip_next),
                tint = idle,
                modifier = Modifier.size(36.dp),
            )
        }
        IconButton(onClick = onCycleRepeatMode) {
            val (icon, tint, descriptionRes) = repeatModeVisual(
                repeatMode = repeatMode,
                accent = accent,
                muted = muted,
            )
            Icon(
                imageVector = icon,
                contentDescription = stringResource(descriptionRes),
                tint = tint,
            )
        }
    }
}

private fun repeatModeVisual(
    repeatMode: QueueRepeatMode,
    accent: androidx.compose.ui.graphics.Color,
    muted: androidx.compose.ui.graphics.Color,
): Triple<ImageVector, androidx.compose.ui.graphics.Color, Int> = when (repeatMode) {
    QueueRepeatMode.OFF -> Triple(
        Icons.Outlined.Repeat,
        muted,
        R.string.player_mode_repeat_off,
    )
    QueueRepeatMode.ALL -> Triple(
        Icons.Outlined.Repeat,
        accent,
        R.string.player_mode_repeat_all,
    )
    QueueRepeatMode.ONE -> Triple(
        Icons.Outlined.RepeatOne,
        accent,
        R.string.player_mode_repeat_one,
    )
}
