package com.ytlite.player

import android.Manifest
import android.content.Context
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
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.ytlite.player.data.preferences.AppPreferences
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
import java.util.Locale

class MainActivity : ComponentActivity() {

    private val notificationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { }

    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(applyAppLocale(newBase, AppPreferences.peekLanguage(newBase)))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestNotificationPermissionIfNeeded()
        handleOpenPlayerIntent(intent)
        enableEdgeToEdge()
        val appPreferences = AppPreferences.getInstance(this)
        setContent {
            val nightMode by appPreferences.nightModeEnabled.collectAsStateWithLifecycle(
                initialValue = AppPreferences.peekNightMode(this),
            )
            YTLiteTheme(darkTheme = nightMode) {
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

    companion object {
        fun applyAppLocale(context: Context, languageTag: String): Context {
            if (languageTag == AppPreferences.LANGUAGE_SYSTEM || languageTag.isBlank()) {
                return context
            }
            val locale = when (languageTag) {
                AppPreferences.LANGUAGE_ZH -> Locale.SIMPLIFIED_CHINESE
                AppPreferences.LANGUAGE_EN -> Locale.ENGLISH
                else -> Locale.forLanguageTag(languageTag)
            }
            Locale.setDefault(locale)
            val config = Configuration(context.resources.configuration)
            config.setLocale(locale)
            return context.createConfigurationContext(config)
        }
    }
}
