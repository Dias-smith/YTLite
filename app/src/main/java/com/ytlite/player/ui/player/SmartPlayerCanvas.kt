package com.ytlite.player.ui.player

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Audiotrack
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PictureInPictureAlt
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalMinimumInteractiveComponentSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.media3.common.Player
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.ytlite.player.R
import com.ytlite.player.playback.DeviceRam
import kotlinx.coroutines.delay

private val OverlayIconBackground = Color.Black.copy(alpha = 0.5f)
private val OverlayGradientEnd = Color.Black.copy(alpha = 0.78f)
private const val OverlayAutoHideDelayMs = 5_000L

@Composable
fun SmartPlayerCanvas(
    player: Player?,
    thumbnailUrl: String,
    surfaceMode: PlayerSurfaceMode,
    positionMs: Long,
    durationMs: Long,
    isPlaying: Boolean,
    onSurfaceModeChange: (PlayerSurfaceMode) -> Unit,
    onFullscreenClick: () -> Unit,
    onPictureInPictureClick: () -> Unit,
    onSeek: (Long) -> Unit,
    onTogglePlayPause: () -> Unit,
    onSkipPrevious: () -> Unit,
    onSkipNext: () -> Unit,
    modifier: Modifier = Modifier,
    showPictureInPicture: Boolean = true,
    onBack: (() -> Unit)? = null,
) {
    val context = LocalContext.current
    val pipAvailable = rememberPictureInPictureAvailable()
    val resolvedMode = remember(surfaceMode, context) {
        when (surfaceMode) {
            PlayerSurfaceMode.Auto -> {
                if (DeviceRam.isLowRamDevice(context)) PlayerSurfaceMode.AudioPowerSave
                else PlayerSurfaceMode.Video
            }
            else -> surfaceMode
        }
    }
    val primaryColor = MaterialTheme.colorScheme.primary

    var controlsVisible by remember { mutableStateOf(true) }
    var interactionToken by remember { mutableIntStateOf(0) }

    fun revealControls() {
        controlsVisible = true
        interactionToken++
    }

    LaunchedEffect(interactionToken, controlsVisible, isPlaying) {
        if (!controlsVisible || !isPlaying) return@LaunchedEffect
        delay(OverlayAutoHideDelayMs)
        controlsVisible = false
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
                    useController = false,
                )
            }
            else -> {
                AudioPowerSaveSurface(
                    thumbnailUrl = thumbnailUrl,
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }

        if (!controlsVisible) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        onClick = ::revealControls,
                    ),
            )
        }

        AnimatedVisibility(
            visible = controlsVisible,
            enter = fadeIn(),
            exit = fadeOut(),
        ) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .pointerInput(Unit) {
                        detectTapGestures { revealControls() }
                    },
            ) {
                Box(
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .fillMaxWidth()
                        .height(72.dp)
                        .background(
                            Brush.verticalGradient(
                                colors = listOf(OverlayGradientEnd, Color.Transparent),
                            ),
                        )
                        .padding(horizontal = 4.dp, vertical = 4.dp),
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        if (onBack != null) {
                            PlayerOverlayIconButton(
                                onClick = {
                                    revealControls()
                                    onBack()
                                },
                                size = 36.dp,
                            ) {
                                Icon(
                                    imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                                    contentDescription = stringResource(R.string.player_back),
                                    tint = Color.White,
                                )
                            }
                        } else {
                            Box(modifier = Modifier.size(36.dp))
                        }
                        Box(modifier = Modifier.weight(1f))
                        PlayerOverlayButtonGroup(cornerRadius = 20.dp) {
                            PlayerOverlayPlainIconButton(
                                onClick = {
                                    revealControls()
                                    val next = when (resolvedMode) {
                                        PlayerSurfaceMode.Video -> PlayerSurfaceMode.AudioPowerSave
                                        else -> PlayerSurfaceMode.Video
                                    }
                                    onSurfaceModeChange(next)
                                },
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
                            if (showPictureInPicture && pipAvailable && resolvedMode == PlayerSurfaceMode.Video) {
                                PlayerOverlayPlainIconButton(
                                    onClick = {
                                        revealControls()
                                        onPictureInPictureClick()
                                    },
                                ) {
                                    Icon(
                                        imageVector = Icons.Filled.PictureInPictureAlt,
                                        contentDescription = stringResource(R.string.player_pip),
                                        tint = Color.White,
                                    )
                                }
                            }
                            PlayerOverlayPlainIconButton(
                                onClick = {
                                    revealControls()
                                    onFullscreenClick()
                                },
                            ) {
                                Icon(
                                    imageVector = Icons.Filled.Fullscreen,
                                    contentDescription = stringResource(R.string.player_fullscreen),
                                    tint = Color.White,
                                )
                            }
                        }
                    }
                }

                PlayerOverlayButtonGroup(
                    modifier = Modifier.align(Alignment.Center),
                    cornerRadius = 28.dp,
                    horizontalPadding = 8.dp,
                ) {
                    PlayerOverlayPlainIconButton(
                        onClick = {
                            revealControls()
                            onSkipPrevious()
                        },
                        size = 44.dp,
                    ) {
                        Icon(
                            imageVector = Icons.Filled.SkipPrevious,
                            contentDescription = stringResource(R.string.player_skip_previous),
                            tint = Color.White,
                            modifier = Modifier.size(32.dp),
                        )
                    }
                    PlayerOverlayPlainIconButton(
                        onClick = {
                            revealControls()
                            onTogglePlayPause()
                        },
                        size = 56.dp,
                    ) {
                        Icon(
                            imageVector = if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                            contentDescription = null,
                            tint = Color.White,
                            modifier = Modifier.size(40.dp),
                        )
                    }
                    PlayerOverlayPlainIconButton(
                        onClick = {
                            revealControls()
                            onSkipNext()
                        },
                        size = 44.dp,
                    ) {
                        Icon(
                            imageVector = Icons.Filled.SkipNext,
                            contentDescription = stringResource(R.string.player_skip_next),
                            tint = Color.White,
                            modifier = Modifier.size(32.dp),
                        )
                    }
                }

                Box(
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .fillMaxWidth()
                        .height(72.dp)
                        .background(
                            Brush.verticalGradient(
                                colors = listOf(Color.Transparent, OverlayGradientEnd),
                            ),
                        )
                        .padding(horizontal = 12.dp, vertical = 8.dp),
                    contentAlignment = Alignment.BottomCenter,
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = formatPlaybackTime(positionMs),
                            style = MaterialTheme.typography.labelSmall,
                            color = Color.White,
                            modifier = Modifier.padding(end = 8.dp),
                        )
                        PlayerProgressBar(
                            positionMs = positionMs,
                            durationMs = durationMs,
                            onSeek = { position ->
                                revealControls()
                                onSeek(position)
                            },
                            activeColor = primaryColor,
                            modifier = Modifier.weight(1f),
                        )
                        Text(
                            text = formatPlaybackTime(durationMs),
                            style = MaterialTheme.typography.labelSmall,
                            color = Color.White,
                            modifier = Modifier.padding(start = 8.dp),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun PlayerOverlayButtonGroup(
    modifier: Modifier = Modifier,
    cornerRadius: Dp = 20.dp,
    horizontalPadding: Dp = 4.dp,
    content: @Composable () -> Unit,
) {
    CompositionLocalProvider(LocalMinimumInteractiveComponentSize provides 0.dp) {
        Row(
            modifier = modifier
                .background(OverlayIconBackground, RoundedCornerShape(cornerRadius))
                .padding(horizontal = horizontalPadding),
            horizontalArrangement = Arrangement.spacedBy(0.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            content()
        }
    }
}

@Composable
private fun PlayerOverlayPlainIconButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    size: Dp = 36.dp,
    content: @Composable () -> Unit,
) {
    IconButton(
        onClick = onClick,
        modifier = modifier.size(size),
    ) {
        content()
    }
}

@Composable
private fun PlayerOverlayIconButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    size: Dp = 36.dp,
    content: @Composable () -> Unit,
) {
    IconButton(
        onClick = onClick,
        modifier = modifier
            .size(size)
            .background(OverlayIconBackground, CircleShape),
    ) {
        content()
    }
}

@Composable
private fun PlayerProgressBar(
    positionMs: Long,
    durationMs: Long,
    onSeek: (Long) -> Unit,
    activeColor: Color,
    modifier: Modifier = Modifier,
    trackHeight: Dp = 3.dp,
    thumbSize: Dp = 10.dp,
) {
    val fraction = if (durationMs > 0) {
        (positionMs.toFloat() / durationMs).coerceIn(0f, 1f)
    } else {
        0f
    }
    val inactiveColor = Color.White.copy(alpha = 0.35f)

    BoxWithConstraints(
        modifier = modifier
            .height(thumbSize)
            .pointerInput(durationMs) {
                detectTapGestures { offset ->
                    if (durationMs <= 0L) return@detectTapGestures
                    val seekFraction = (offset.x / size.width).coerceIn(0f, 1f)
                    onSeek((seekFraction * durationMs).toLong())
                }
            }
            .pointerInput(durationMs) {
                detectHorizontalDragGestures { change, _ ->
                    if (durationMs <= 0L) return@detectHorizontalDragGestures
                    change.consume()
                    val seekFraction = (change.position.x / size.width).coerceIn(0f, 1f)
                    onSeek((seekFraction * durationMs).toLong())
                }
            },
        contentAlignment = Alignment.CenterStart,
    ) {
        val trackWidth = maxWidth
        val thumbOffset = trackWidth * fraction - thumbSize / 2

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(trackHeight)
                .align(Alignment.CenterStart)
                .background(inactiveColor, CircleShape),
        )
        Box(
            modifier = Modifier
                .fillMaxWidth(fraction)
                .height(trackHeight)
                .align(Alignment.CenterStart)
                .background(activeColor, CircleShape),
        )
        Box(
            modifier = Modifier
                .offset(x = thumbOffset.coerceIn(0.dp, trackWidth - thumbSize))
                .size(thumbSize)
                .background(activeColor, CircleShape),
        )
    }
}

@Composable
private fun AudioPowerSaveSurface(
    thumbnailUrl: String,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    Box(modifier = modifier.background(Color.Black)) {
        AsyncImage(
            model = ImageRequest.Builder(context)
                .data(thumbnailUrl)
                .allowRgb565(true)
                .crossfade(false)
                .build(),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
    }
}
