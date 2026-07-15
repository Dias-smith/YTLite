package com.ytlite.player.download

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import com.ytlite.player.MainActivity
import com.ytlite.player.R
import com.ytlite.player.data.local.entity.DownloadTaskStatus
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

class DownloadForegroundService : Service() {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var observeJob: Job? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        promoteToForeground(buildNotification(getString(R.string.download_notification_idle), 0, 0))
        observeJob = scope.launch {
            DownloadRepository.getInstance(this@DownloadForegroundService)
                .observeActiveTasks()
                .map { tasks ->
                    tasks.filter {
                        it.status == DownloadTaskStatus.RUNNING || it.status == DownloadTaskStatus.QUEUED
                    }
                }
                .distinctUntilChanged()
                .collectLatest { active ->
                    if (active.isEmpty()) {
                        // Brief grace so completing one task can enqueue the next
                        // without tearing down the FGS and immediately restarting it.
                        delay(STOP_GRACE_MS)
                        val stillIdle = DownloadRepository.getInstance(this@DownloadForegroundService)
                            .hasActiveWork()
                            .not()
                        if (stillIdle) {
                            ServiceCompat.stopForeground(
                                this@DownloadForegroundService,
                                ServiceCompat.STOP_FOREGROUND_REMOVE,
                            )
                            stopSelf()
                        }
                        return@collectLatest
                    }
                    val running = active.firstOrNull { it.status == DownloadTaskStatus.RUNNING }
                        ?: active.first()
                    val progress = if (running.totalBytes > 0) {
                        ((running.downloadedBytes * 100) / running.totalBytes).toInt().coerceIn(0, 100)
                    } else {
                        0
                    }
                    val text = if (running.status == DownloadTaskStatus.RUNNING) {
                        getString(R.string.download_notification_progress, running.title, progress)
                    } else {
                        getString(R.string.download_notification_queued, active.size)
                    }
                    val notification = buildNotification(
                        text,
                        progress,
                        if (running.totalBytes > 0) 100 else 0,
                    )
                    val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                    nm.notify(NOTIFICATION_ID, notification)
                }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Repository drives the queue; do not restart with START_STICKY when idle.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        observeJob?.cancel()
        scope.cancel()
        super.onDestroy()
    }

    private fun promoteToForeground(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.download_notification_channel),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = getString(R.string.download_notification_channel_description)
        }
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(channel)
    }

    private fun buildNotification(content: String, progress: Int, max: Int): Notification {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(EXTRA_OPEN_DOWNLOADS, true)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.download_notification_title))
            .setContentText(content)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentIntent(open)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
        if (max > 0) {
            builder.setProgress(max, progress, false)
        } else {
            builder.setProgress(0, 0, true)
        }
        return builder.build()
    }

    companion object {
        const val CHANNEL_ID = "ytlite_downloads"
        const val NOTIFICATION_ID = 4201
        const val EXTRA_OPEN_DOWNLOADS = "open_downloads"
        private const val STOP_GRACE_MS = 400L
    }
}
