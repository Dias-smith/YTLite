package com.ytlite.player.ui.player

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.Player
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView

@Composable
fun VideoPlayerView(
    player: Player?,
    modifier: Modifier = Modifier,
    useController: Boolean = true,
) {
    PlayerSurface(
        player = player,
        modifier = modifier,
        useController = useController,
    )
}

@Composable
fun MiniPlayerSurface(
    player: Player?,
    modifier: Modifier = Modifier,
) {
    PlayerSurface(
        player = player,
        modifier = modifier,
        useController = false,
        resizeMode = AspectRatioFrameLayout.RESIZE_MODE_ZOOM,
    )
}

@Composable
private fun PlayerSurface(
    player: Player?,
    modifier: Modifier = Modifier,
    useController: Boolean = true,
    resizeMode: Int = AspectRatioFrameLayout.RESIZE_MODE_FIT,
) {
    if (player == null) return

    val stablePlayer = remember(player) { player }

    AndroidView(
        factory = { context ->
            PlayerView(context).apply {
                this.player = stablePlayer
                this.useController = useController
                controllerShowTimeoutMs = 3000
                this.resizeMode = resizeMode
                setShowBuffering(PlayerView.SHOW_BUFFERING_NEVER)
            }
        },
        update = { view ->
            if (view.player !== stablePlayer) {
                view.player = stablePlayer
            }
            view.useController = useController
            view.resizeMode = resizeMode
        },
        onRelease = { view ->
            view.player = null
        },
        modifier = modifier,
    )
}
