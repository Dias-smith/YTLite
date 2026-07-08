package com.ytlite.player.ui.player

import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
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

        setContent {
            YTLiteTheme {
                val player by PlaybackManager.playerState.collectAsStateWithLifecycle()
                val positionMs by PlaybackManager.positionMs.collectAsStateWithLifecycle()
                val durationMs by PlaybackManager.durationMs.collectAsStateWithLifecycle()

                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color.Black),
                ) {
                    SmartPlayerCanvas(
                        player = player,
                        thumbnailUrl = thumbnailUrl,
                        surfaceMode = PlayerSurfaceMode.Video,
                        positionMs = positionMs,
                        durationMs = durationMs,
                        onSurfaceModeChange = { },
                        onFullscreenClick = { finish() },
                        onCcClick = { },
                        onSettingsClick = { },
                        modifier = Modifier.fillMaxSize(),
                    )
                }
            }
        }
    }

    companion object {
        private const val EXTRA_THUMBNAIL_URL = "thumbnail_url"

        fun createIntent(context: Context, thumbnailUrl: String): Intent =
            Intent(context, FullscreenPlayerActivity::class.java).apply {
                putExtra(EXTRA_THUMBNAIL_URL, thumbnailUrl)
            }
    }
}
