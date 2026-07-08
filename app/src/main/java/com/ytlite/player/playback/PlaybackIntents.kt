package com.ytlite.player.playback

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.ytlite.player.MainActivity

object PlaybackIntents {

    const val ACTION_OPEN_PLAYER = "com.ytlite.player.action.OPEN_PLAYER"
    const val EXTRA_VIDEO_ID = "extra_video_id"

    fun openPlayerIntent(context: Context, videoId: String? = null): Intent =
        Intent(context, MainActivity::class.java).apply {
            action = ACTION_OPEN_PLAYER
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            if (!videoId.isNullOrBlank()) {
                putExtra(EXTRA_VIDEO_ID, videoId)
            }
        }

    fun sessionActivityPendingIntent(context: Context): PendingIntent {
        val intent = openPlayerIntent(context)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getActivity(context, REQUEST_CODE_SESSION, intent, flags)
    }

    fun extractVideoId(intent: Intent?): String? =
        intent?.getStringExtra(EXTRA_VIDEO_ID)?.takeIf { it.isNotBlank() }

    private const val REQUEST_CODE_SESSION = 1001
}
