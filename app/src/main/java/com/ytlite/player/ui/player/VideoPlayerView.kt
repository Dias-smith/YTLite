package com.ytlite.player.ui.player

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView

@Composable
fun VideoPlayerView(
    streamUrl: String,
    modifier: Modifier = Modifier,
    playWhenReady: Boolean = true,
) {
    val context = LocalContext.current
    val exoPlayer = remember {
        ExoPlayer.Builder(context.applicationContext).build()
    }

    DisposableEffect(streamUrl) {
        exoPlayer.setMediaItem(MediaItem.fromUri(streamUrl))
        exoPlayer.repeatMode = Player.REPEAT_MODE_OFF
        exoPlayer.playWhenReady = playWhenReady
        exoPlayer.prepare()
        onDispose {
            exoPlayer.stop()
            exoPlayer.clearMediaItems()
        }
    }

    DisposableEffect(Unit) {
        onDispose { exoPlayer.release() }
    }

    AndroidView(
        factory = { ctx ->
            PlayerView(ctx).apply {
                player = exoPlayer
                useController = true
                controllerShowTimeoutMs = 3000
            }
        },
        modifier = modifier,
    )
}
