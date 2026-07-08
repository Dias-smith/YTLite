package com.ytlite.player.playback

import android.app.ActivityManager
import android.content.Context

object DeviceRam {

    const val LOW_RAM_THRESHOLD_BYTES = 4L * 1024 * 1024 * 1024

    fun totalMemBytes(context: Context): Long {
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val info = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(info)
        return info.totalMem
    }

    fun isLowRamDevice(context: Context): Boolean =
        totalMemBytes(context) < LOW_RAM_THRESHOLD_BYTES
}
