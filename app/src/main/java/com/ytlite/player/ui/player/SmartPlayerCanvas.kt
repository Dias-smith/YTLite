package com.ytlite.player.ui.player

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Audiotrack
import androidx.compose.material.icons.filled.ClosedCaption
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.media3.common.Player
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.ytlite.player.R
import com.ytlite.player.playback.DeviceRam
import kotlin.math.max

@Composable
fun SmartPlayerCanvas(
    player: Player?,
    thumbnailUrl: String,
    surfaceMode: PlayerSurfaceMode,
    positionMs: Long,
    durationMs: Long,
    onSurfaceModeChange: (PlayerSurfaceMode) -> Unit,
    onFullscreenClick: () -> Unit,
    onCcClick: () -> Unit,
    onSettingsClick: () -> Unit,
    modifier: Modifier = Modifier,
    overlay: @Composable () -> Unit = {},
) {
    val context = LocalContext.current
    val resolvedMode = remember(surfaceMode, context) {
        when (surfaceMode) {
            PlayerSurfaceMode.Auto -> {
                if (DeviceRam.isLowRamDevice(context)) PlayerSurfaceMode.AudioPowerSave
                else PlayerSurfaceMode.Video
            }
            else -> surfaceMode
        }
    }

    Box(
        modifier = modifier
            .fillMaxWidth()
            .aspectRatio(16f / 9f)
            .background(Color.Black),
    ) {
        when (resolvedMode) {
            PlayerSurfaceMode.Video -> {
                VideoPlayerView(
                    player = player,
                    modifier = Modifier.fillMaxSize(),
                )
            }
            else -> {
                AudioPowerSaveSurface(
                    thumbnailUrl = thumbnailUrl,
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }

        overlay()

        Row(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(4.dp),
            horizontalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            IconButton(
                onClick = {
                    val next = when (resolvedMode) {
                        PlayerSurfaceMode.Video -> PlayerSurfaceMode.AudioPowerSave
                        else -> PlayerSurfaceMode.Video
                    }
                    onSurfaceModeChange(next)
                },
                modifier = Modifier.size(36.dp),
            ) {
                Icon(
                    imageVector = if (resolvedMode == PlayerSurfaceMode.Video) {
                        Icons.Filled.Audiotrack
                    } else {
                        Icons.Filled.Videocam
                    },
                    contentDescription = stringResource(R.string.player_toggle_surface_mode),
                    tint = Color.White,
                )
            }
            IconButton(onClick = onCcClick, modifier = Modifier.size(36.dp)) {
                Icon(
                    imageVector = Icons.Filled.ClosedCaption,
                    contentDescription = stringResource(R.string.player_cc),
                    tint = Color.White,
                )
            }
            IconButton(onClick = onSettingsClick, modifier = Modifier.size(36.dp)) {
                Icon(
                    imageVector = Icons.Filled.Settings,
                    contentDescription = stringResource(R.string.player_settings),
                    tint = Color.White,
                )
            }
        }

        Row(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(8.dp),
        ) {
            Text(
                text = "${formatDuration(positionMs)} / ${formatDuration(durationMs)}",
                style = MaterialTheme.typography.labelMedium,
                color = Color.White,
            )
        }

        IconButton(
            onClick = onFullscreenClick,
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(4.dp)
                .size(36.dp),
        ) {
            Icon(
                imageVector = Icons.Filled.Fullscreen,
                contentDescription = stringResource(R.string.player_fullscreen),
                tint = Color.White,
            )
        }
    }
}

@Composable
private fun AudioPowerSaveSurface(
    thumbnailUrl: String,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    Box(modifier = modifier.background(Color(0xFF121212))) {
        AsyncImage(
            model = ImageRequest.Builder(context)
                .data(thumbnailUrl)
                .allowRgb565(true)
                .crossfade(false)
                .build(),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .fillMaxSize()
                .padding(32.dp),
        )
        Text(
            text = stringResource(R.string.player_lyrics_placeholder),
            style = MaterialTheme.typography.bodyMedium,
            color = Color.White.copy(alpha = 0.7f),
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 24.dp),
        )
    }
}

private fun formatDuration(ms: Long): String {
    if (ms <= 0L) return "0:00"
    val totalSeconds = max(0L, ms / 1_000)
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return "%d:%02d".format(minutes, seconds)
}
