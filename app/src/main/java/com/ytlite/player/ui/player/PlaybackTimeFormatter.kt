package com.ytlite.player.ui.player

import kotlin.math.max

fun formatPlaybackTime(ms: Long): String {
    if (ms <= 0L) return "0:00"
    val totalSeconds = max(0L, ms / 1_000)
    val hours = totalSeconds / 3_600
    val minutes = (totalSeconds % 3_600) / 60
    val seconds = totalSeconds % 60
    return if (hours > 0) {
        "%d:%02d:%02d".format(hours, minutes, seconds)
    } else {
        "%d:%02d".format(minutes, seconds)
    }
}
