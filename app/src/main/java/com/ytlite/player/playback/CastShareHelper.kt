package com.ytlite.player.playback

import android.content.Context
import android.content.Intent
import android.provider.Settings

object CastShareHelper {

    fun shareVideo(context: Context, videoId: String) {
        val url = "https://www.youtube.com/watch?v=$videoId"
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, url)
        }
        context.startActivity(Intent.createChooser(intent, null))
    }

    fun openCastOrShare(context: Context, videoId: String): CastAction {
        val castIntent = Intent(Settings.ACTION_CAST_SETTINGS)
        if (castIntent.resolveActivity(context.packageManager) != null) {
            return CastAction.Launch(castIntent)
        }
        val wirelessIntent = Intent("android.settings.WIRELESS_DISPLAY_SETTINGS")
        if (wirelessIntent.resolveActivity(context.packageManager) != null) {
            return CastAction.Launch(wirelessIntent)
        }
        shareVideo(context, videoId)
        return CastAction.Shared
    }

    sealed class CastAction {
        data class Launch(val intent: Intent) : CastAction()
        data object Shared : CastAction()
    }
}
