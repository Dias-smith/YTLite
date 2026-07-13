package com.ytlite.player.ui.player

import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.ytlite.player.playback.PlaybackManager
import com.ytlite.player.ui.theme.YTLiteTheme

class FullscreenPlayerActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val thumbnailUrl = intent.getStringExtra(EXTRA_THUMBNAIL_URL).orEmpty()
        val surfaceMode = intent.getStringExtra(EXTRA_SURFACE_MODE)
            ?.let { name -> runCatching { PlayerSurfaceMode.valueOf(name) }.getOrNull() }
            ?: PlayerSurfaceMode.Video

        setContent {
            YTLiteTheme {
                val player by PlaybackManager.playerState.collectAsStateWithLifecycle()
                val isPlaying by PlaybackManager.isPlaying.collectAsStateWithLifecycle()
                val positionMs by PlaybackManager.positionMs.collectAsStateWithLifecycle()
                val durationMs by PlaybackManager.durationMs.collectAsStateWithLifecycle()
                val isInPipMode by PlayerPipState.isInPictureInPictureMode.collectAsStateWithLifecycle()

                DisposableEffect(isPlaying) {
                    if (isPlaying) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    onDispose {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                }

                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color.Black),
                ) {
                    SmartPlayerCanvas(
                        player = player,
                        thumbnailUrl = thumbnailUrl,
                        surfaceMode = surfaceMode,
                        positionMs = positionMs,
                        durationMs = durationMs,
                        isPlaying = isPlaying,
                        onSurfaceModeChange = { },
                        onFullscreenClick = {
                            if (isInPipMode) {
                                exitPlayerPictureInPicture()
                            } else {
                                finish()
                            }
                        },
                        onPictureInPictureClick = {
                            PlayerPipState.requestEnterPictureInPictureAfterFullscreenExit()
                            PlaybackManager.setInlinePlayerSurfaceAttached(true)
                            finish()
                        },
                        onSeek = PlaybackManager::seekTo,
                        onTogglePlayPause = PlaybackManager::togglePlayPause,
                        onSkipPrevious = PlaybackManager::skipToPreviousInQueue,
                        onSkipNext = PlaybackManager::skipToNextInQueue,
                        modifier = Modifier.fillMaxSize(),
                        layout = if (isInPipMode) PlayerCanvasLayout.Pip else PlayerCanvasLayout.Fullscreen,
                        onBack = if (isInPipMode) {
                            { exitPlayerPictureInPicture() }
                        } else {
                            null
                        },
                    )
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (isInPictureInPictureMode) {
            applyPlayerPictureInPictureParams()
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        handlePlayerPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
    }

    override fun onPictureInPictureUiStateChanged(pipState: android.app.PictureInPictureUiState) {
        super.onPictureInPictureUiStateChanged(pipState)
        handlePlayerPictureInPictureUiStateChanged(pipState)
    }

    override fun onDestroy() {
        PlaybackManager.setInlinePlayerSurfaceAttached(true)
        super.onDestroy()
    }

    companion object {
        private const val EXTRA_THUMBNAIL_URL = "thumbnail_url"
        private const val EXTRA_SURFACE_MODE = "surface_mode"

        fun createIntent(
            context: Context,
            thumbnailUrl: String,
            surfaceMode: PlayerSurfaceMode = PlayerSurfaceMode.Video,
        ): Intent =
            Intent(context, FullscreenPlayerActivity::class.java).apply {
                putExtra(EXTRA_THUMBNAIL_URL, thumbnailUrl)
                putExtra(EXTRA_SURFACE_MODE, surfaceMode.name)
            }
    }
}
