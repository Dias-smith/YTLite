package com.ytlite.player.ui.player

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Rect
import android.os.Build
import android.util.Rational
import androidx.activity.ComponentActivity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import android.content.res.Configuration

fun buildPlayerPictureInPictureParams(
    sourceRectHint: Rect? = PlayerPipState.sourceRectHint,
): PictureInPictureParams {
    val builder = PictureInPictureParams.Builder()
        .setAspectRatio(Rational(16, 9))
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        builder.setAutoEnterEnabled(false)
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
    setPictureInPictureParams(buildPlayerPictureInPictureParams(sourceRectHint))
}

fun Activity.enterPlayerPictureInPicture(
    sourceRectHint: Rect? = PlayerPipState.sourceRectHint,
) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    if (!packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) return
    PlayerPipState.setInPictureInPictureMode(true)
    applyPlayerPictureInPictureParams(sourceRectHint)
    enterPictureInPictureMode(buildPlayerPictureInPictureParams(sourceRectHint))
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
