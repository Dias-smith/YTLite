package com.ytlite.player.playback

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.media.AudioManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.DefaultMediaNotificationProvider
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import com.ytlite.player.R
import com.ytlite.player.data.network.InnerTubeConfig

@UnstableApi
class PlaybackService : MediaSessionService() {

    private var mediaSession: MediaSession? = null
    private var becomingNoisyReceiver: BroadcastReceiver? = null

    override fun onCreate() {
        super.onCreate()
        OemPlaybackCompat.logProfile()
        ensureNotificationChannel()
        startForegroundImmediately()

        val player = buildPlayer()
        mediaSession = MediaSession.Builder(this, player)
            .setSessionActivity(PlaybackIntents.sessionActivityPendingIntent(this))
            .build()

        setMediaNotificationProvider(buildNotificationProvider())
        PlaybackManager.onServiceCreated(player, mediaSession!!)
        registerBecomingNoisyReceiver()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? =
        mediaSession

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Keep background playback when the user swipes the app from recents.
        if (mediaSession?.player?.playWhenReady == true) {
            return
        }
        stopSelf()
    }

    override fun onDestroy() {
        unregisterBecomingNoisyReceiver()
        PlaybackManager.onServiceDestroyed()
        mediaSession?.run {
            player.release()
            release()
        }
        mediaSession = null
        super.onDestroy()
    }

    private fun buildPlayer(): ExoPlayer {
        val httpDataSourceFactory = DefaultHttpDataSource.Factory()
            .setUserAgent(InnerTubeConfig.USER_AGENT)
            .setDefaultRequestProperties(
                mapOf("Referer" to "${InnerTubeConfig.BASE_URL}/"),
            )
        val cacheDataSourceFactory = CacheDataSource.Factory()
            .setCache(PlaybackMediaCache.get(this))
            .setUpstreamDataSourceFactory(httpDataSourceFactory)
            .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)
        val mediaSourceFactory = ConditionalCacheMediaSourceFactory(
            httpDataSourceFactory = httpDataSourceFactory,
            cacheDataSourceFactory = cacheDataSourceFactory,
        )
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
            .build()
        return ExoPlayer.Builder(this)
            .setMediaSourceFactory(mediaSourceFactory)
            .setWakeMode(C.WAKE_MODE_NETWORK)
            .build()
            .apply {
                setAudioAttributes(audioAttributes, /* handleAudioFocus= */ true)
                setHandleAudioBecomingNoisy(true)
            }
    }

    private fun buildNotificationProvider(): DefaultMediaNotificationProvider =
        DefaultMediaNotificationProvider.Builder(this)
            .setNotificationId(NOTIFICATION_ID)
            .setChannelId(CHANNEL_ID)
            .setChannelName(R.string.playback_notification_channel)
            .build()
            .apply {
                setSmallIcon(R.drawable.ic_notification_playback)
            }

    private fun startForegroundImmediately() {
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification_playback)
            .setContentTitle(getString(R.string.playback_service_starting))
            .setPriority(
                if (OemPlaybackCompat.prefersPersistentForeground()) {
                    NotificationCompat.PRIORITY_DEFAULT
                } else {
                    NotificationCompat.PRIORITY_LOW
                },
            )
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setSilent(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.playback_notification_channel),
            OemPlaybackCompat.notificationImportance(),
        ).apply {
            description = getString(R.string.playback_notification_channel_description)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
        }
        manager.createNotificationChannel(channel)
    }

    private fun registerBecomingNoisyReceiver() {
        if (becomingNoisyReceiver != null) return
        becomingNoisyReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (AudioManager.ACTION_AUDIO_BECOMING_NOISY == intent.action) {
                    PlaybackManager.pause()
                }
            }
        }
        val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(becomingNoisyReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(becomingNoisyReceiver, filter)
        }
    }

    private fun unregisterBecomingNoisyReceiver() {
        val receiver = becomingNoisyReceiver ?: return
        runCatching { unregisterReceiver(receiver) }
        becomingNoisyReceiver = null
    }

    companion object {
        const val CHANNEL_ID = "ytlite_playback"
        const val NOTIFICATION_ID = 1001
    }
}
