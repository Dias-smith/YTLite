package com.ytlite.player.ui.playback

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.filled.RepeatOne
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.ytlite.player.R
import com.ytlite.player.playback.QueueRepeatMode

@Composable
fun QueueHeader(
    currentTitle: String?,
    repeatMode: QueueRepeatMode,
    shuffleEnabled: Boolean,
    onCycleRepeat: () -> Unit,
    onToggleShuffle: () -> Unit,
    onMore: () -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = 8.dp),
        ) {
            Text(
                text = stringResource(R.string.player_queue_title),
                style = MaterialTheme.typography.titleMedium,
                color = Color.White,
            )
            currentTitle?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.bodySmall,
                    color = Color(0xFFAAAAAA),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        IconButton(onClick = onCycleRepeat) {
            Icon(
                imageVector = when (repeatMode) {
                    QueueRepeatMode.ONE -> Icons.Filled.RepeatOne
                    else -> Icons.Filled.Repeat
                },
                contentDescription = stringResource(R.string.player_repeat),
                tint = if (repeatMode != QueueRepeatMode.OFF) Color.White else Color(0xFF888888),
            )
        }
        IconButton(onClick = onToggleShuffle) {
            Icon(
                imageVector = Icons.Filled.Shuffle,
                contentDescription = stringResource(R.string.player_shuffle),
                tint = if (shuffleEnabled) Color.White else Color(0xFF888888),
            )
        }
        IconButton(onClick = onMore) {
            Icon(
                imageVector = Icons.Filled.MoreVert,
                contentDescription = stringResource(R.string.player_settings),
                tint = Color(0xFFAAAAAA),
            )
        }
        IconButton(onClick = onClose) {
            Icon(
                imageVector = Icons.Filled.Close,
                contentDescription = stringResource(R.string.player_close_queue),
                tint = Color(0xFFAAAAAA),
            )
        }
    }
}
