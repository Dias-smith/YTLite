package com.ytlite.player.ui.player

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Rect
import android.os.Build
import android.util.Rational
import androidx.activity.ComponentActivity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import com.ytlite.player.data.preferences.AppPreferences
import com.ytlite.player.playback.PlaybackManager

fun buildPlayerPictureInPictureParams(
    context: android.content.Context,
    sourceRectHint: Rect? = PlayerPipState.sourceRectHint,
): PictureInPictureParams {
    val pipEnabled = AppPreferences.peekPictureInPicture(context)
    val builder = PictureInPictureParams.Builder()
        .setAspectRatio(Rational(16, 9))
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        // Only auto-enter PiP on Home / gesture leave when the setting is on.
        builder.setAutoEnterEnabled(pipEnabled && PlaybackManager.isPlaying.value)
        builder.setSeamlessResizeEnabled(true)
    }
    sourceRectHint?.let { hint ->
        builder.setSourceRectHint(hint)
    }
    return builder.build()
}

fun Activity.applyPlayerPictureInPictureParams(
    sourceRectHint: Rect? = PlayerPipState.sourceRectHint,
) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    if (!packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) return
    setPictureInPictureParams(buildPlayerPictureInPictureParams(this, sourceRectHint))
}

fun Activity.enterPlayerPictureInPicture(
    sourceRectHint: Rect? = PlayerPipState.sourceRectHint,
) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    if (!packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) return
    if (!AppPreferences.peekPictureInPicture(this)) return
    PlayerPipState.setInPictureInPictureMode(true)
    applyPlayerPictureInPictureParams(sourceRectHint)
    enterPictureInPictureMode(buildPlayerPictureInPictureParams(this, sourceRectHint))
}

/**
 * Home / Recents leave: enter PiP only when enabled; otherwise keep
 * [com.ytlite.player.playback.PlaybackService] audio in background without a PiP window.
 */
fun Activity.handlePlayerUserLeaveHint() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    // Always refresh params first so Android 12+ auto-enter matches the setting
    // (critical when leaving from the expanded player / detail screen).
    applyPlayerPictureInPictureParams()
    if (!AppPreferences.peekPictureInPicture(this)) return
    if (!PlaybackManager.isPlaying.value) return
    if (isInPictureInPictureMode) return
    enterPlayerPictureInPicture()
}

fun Activity.exitPlayerPictureInPicture() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isInPictureInPictureMode) {
        val intent = Intent(this, this::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        startActivity(intent)
    }
}

fun ComponentActivity.handlePlayerPictureInPictureModeChanged(
    isInPictureInPictureMode: Boolean,
    @Suppress("UNUSED_PARAMETER") newConfig: Configuration,
) {
    if (isInPictureInPictureMode && !AppPreferences.peekPictureInPicture(this)) {
        // Stale auto-enter: close the floating window, keep PlaybackService audio.
        PlayerPipState.setInPictureInPictureMode(false)
        val intent = Intent(this, this::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        startActivity(intent)
        window.decorView.post {
            moveTaskToBack(true)
        }
        return
    }
    PlayerPipState.setInPictureInPictureMode(isInPictureInPictureMode)
    if (isInPictureInPictureMode) {
        applyPlayerPictureInPictureParams()
    }
}

fun ComponentActivity.handlePlayerPictureInPictureUiStateChanged(
    pipState: android.app.PictureInPictureUiState,
) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM &&
        pipState.isTransitioningToPip
    ) {
        // Ignore / block system PiP transition when the user disabled Picture in Picture.
        if (!AppPreferences.peekPictureInPicture(this)) {
            applyPlayerPictureInPictureParams()
            return
        }
        PlayerPipState.setInPictureInPictureMode(true)
        applyPlayerPictureInPictureParams()
    }
}

@Composable
fun rememberPictureInPictureAvailable(): Boolean {
    val context = LocalContext.current
    return remember(context) {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }
}
