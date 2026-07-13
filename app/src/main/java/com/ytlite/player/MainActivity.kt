package com.ytlite.player

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.core.content.ContextCompat
import com.ytlite.player.playback.PlaybackIntents
import com.ytlite.player.playback.PlaybackManager
import com.ytlite.player.playback.PlaybackNavigation
import com.ytlite.player.ui.navigation.YTLiteNavHost
import com.ytlite.player.ui.player.handlePlayerPictureInPictureModeChanged
import com.ytlite.player.ui.player.handlePlayerPictureInPictureUiStateChanged
import com.ytlite.player.ui.player.applyPlayerPictureInPictureParams
import com.ytlite.player.ui.player.enterPlayerPictureInPicture
import com.ytlite.player.ui.player.PlayerPipState
import com.ytlite.player.ui.theme.YTLiteTheme

class MainActivity : ComponentActivity() {

    private val notificationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestNotificationPermissionIfNeeded()
        handleOpenPlayerIntent(intent)
        enableEdgeToEdge()
        setContent {
            YTLiteTheme {
                YTLiteNavHost(modifier = Modifier.fillMaxSize())
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleOpenPlayerIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        if (PlayerPipState.consumePendingEnterPictureInPicture()) {
            window.decorView.post {
                enterPlayerPictureInPicture()
            }
        } else if (isInPictureInPictureMode) {
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

    private fun handleOpenPlayerIntent(intent: Intent?) {
        if (intent?.action != PlaybackIntents.ACTION_OPEN_PLAYER) return
        val videoId = PlaybackIntents.extractVideoId(intent)
            ?: PlaybackManager.nowPlaying.value?.videoId
            ?: return
        PlaybackNavigation.requestOpenPlayer(videoId)
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
            == PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
    }
}
