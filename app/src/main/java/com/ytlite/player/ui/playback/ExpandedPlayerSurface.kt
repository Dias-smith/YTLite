package com.ytlite.player.ui.playback

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.ytlite.player.R
import com.ytlite.player.playback.NowPlaying
import kotlin.math.max

private val ProgressRed = Color(0xFFFF0000)
private val OverlayWhite = Color.White
private val OverlayMuted = Color(0xFFAAAAAA)

@Composable
fun ExpandedPlayerSurface(
    nowPlaying: NowPlaying,
    isPlaying: Boolean,
    positionMs: Long,
    durationMs: Long,
    onSeek: (Long) -> Unit,
    onTogglePlayPause: () -> Unit,
    onSkipPrevious: () -> Unit,
    onSkipNext: () -> Unit,
    onFullscreen: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        AsyncImage(
            model = nowPlaying.thumbnailUrl,
            contentDescription = nowPlaying.title,
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .fillMaxWidth(0.55f)
                .aspectRatio(1f)
                .clip(RoundedCornerShape(4.dp)),
        )
        Text(
            text = nowPlaying.title,
            color = OverlayWhite,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.fillMaxWidth(),
        )
        Text(
            text = nowPlaying.channelName,
            color = OverlayMuted,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.fillMaxWidth(),
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onSkipPrevious) {
                Icon(
                    imageVector = Icons.Filled.SkipPrevious,
                    contentDescription = stringResource(R.string.player_skip_previous),
                    tint = OverlayWhite,
                    modifier = Modifier.size(32.dp),
                )
            }
            IconButton(onClick = onTogglePlayPause, modifier = Modifier.size(56.dp)) {
                Icon(
                    imageVector = if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                    contentDescription = null,
                    tint = OverlayWhite,
                    modifier = Modifier.size(40.dp),
                )
            }
            IconButton(onClick = onSkipNext) {
                Icon(
                    imageVector = Icons.Filled.SkipNext,
                    contentDescription = stringResource(R.string.player_skip_next),
                    tint = OverlayWhite,
                    modifier = Modifier.size(32.dp),
                )
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = formatTime(positionMs),
                color = OverlayMuted,
                style = androidx.compose.material3.MaterialTheme.typography.labelSmall,
            )
            Slider(
                value = if (durationMs > 0) positionMs.toFloat() / durationMs else 0f,
                onValueChange = { fraction ->
                    onSeek((fraction * durationMs).toLong())
                },
                modifier = Modifier
                    .weight(1f)
                    .padding(horizontal = 8.dp),
                colors = SliderDefaults.colors(
                    thumbColor = ProgressRed,
                    activeTrackColor = ProgressRed,
                    inactiveTrackColor = Color(0xFF424242),
                ),
            )
            Text(
                text = formatTime(durationMs),
                color = OverlayMuted,
                style = androidx.compose.material3.MaterialTheme.typography.labelSmall,
            )
        }
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
            IconButton(onClick = onFullscreen) {
                Icon(
                    imageVector = Icons.Filled.Fullscreen,
                    contentDescription = stringResource(R.string.player_fullscreen),
                    tint = OverlayMuted,
                )
            }
        }
    }
}

private fun formatTime(ms: Long): String {
    val totalSeconds = max(0L, ms) / 1000
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return "%d:%02d".format(minutes, seconds)
}
