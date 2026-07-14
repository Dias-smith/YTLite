package com.ytlite.player.ui.playback

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import coil.compose.AsyncImage
import com.ytlite.player.playback.GlobalPlaybackUiState
import com.ytlite.player.playback.PlaybackManager
import com.ytlite.player.ui.image.thumbnailRequest
import com.ytlite.player.ui.player.MiniPlayerSurface

private val MiniPlayerBackground = Color(0xFF212121)
private val ProgressBlue = Color(0xFF3EA6FF)
private val MiniPlayerBarHeight = 56.dp
/** Landscape thumbnail slot; height matches the bar so it never overflows. */
private const val MiniPlayerMediaAspectRatio = 16f / 9f

@Composable
fun MiniPlayerBar(
    state: GlobalPlaybackUiState,
    onOpenPlayer: () -> Unit,
    onTogglePlayPause: () -> Unit,
    onSkipNext: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val nowPlaying = state.nowPlaying ?: return
    val sharedPlayer by PlaybackManager.playerState.collectAsStateWithLifecycle()
    val hasVideoTrack = rememberPlayerHasVideo(sharedPlayer)
    val progress = if (state.durationMs > 0) {
        (state.positionMs.toFloat() / state.durationMs.toFloat()).coerceIn(0f, 1f)
    } else {
        0f
    }
    val context = LocalContext.current

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
                .height(MiniPlayerBarHeight)
                .padding(end = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(
                modifier = Modifier
                    .weight(1f)
                    .clickable(onClick = onOpenPlayer),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    modifier = Modifier
                        .height(MiniPlayerBarHeight)
                        .aspectRatio(MiniPlayerMediaAspectRatio)
                        .clipToBounds(),
                ) {
                    if (hasVideoTrack && sharedPlayer != null) {
                        MiniPlayerSurface(
                            player = sharedPlayer,
                            modifier = Modifier.fillMaxSize(),
                        )
                    } else {
                        AsyncImage(
                            model = thumbnailRequest(context, nowPlaying.thumbnailUrl),
                            contentDescription = null,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.fillMaxSize(),
                        )
                    }
                }
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .padding(start = 12.dp, end = 8.dp),
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
                        text = nowPlaying.channelName,
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
                    tint = Color.White,
                )
            }
            IconButton(onClick = onSkipNext) {
                Icon(
                    imageVector = Icons.Filled.SkipNext,
                    contentDescription = null,
                    tint = Color.White,
                )
            }
        }
    }
}

@Composable
private fun rememberPlayerHasVideo(player: Player?): Boolean {
    var hasVideo by remember(player) { mutableStateOf(playerHasVideo(player)) }

    DisposableEffect(player) {
        if (player == null) {
            hasVideo = false
            return@DisposableEffect onDispose { }
        }
        val listener = object : Player.Listener {
            override fun onVideoSizeChanged(videoSize: VideoSize) {
                hasVideo = videoSize.width > 0 && videoSize.height > 0
            }

            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                hasVideo = playerHasVideo(player)
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                hasVideo = playerHasVideo(player)
            }
        }
        hasVideo = playerHasVideo(player)
        player.addListener(listener)
        onDispose { player.removeListener(listener) }
    }

    return hasVideo
}

private fun playerHasVideo(player: Player?): Boolean {
    val size = player?.videoSize ?: return false
    return size.width > 0 && size.height > 0
}
