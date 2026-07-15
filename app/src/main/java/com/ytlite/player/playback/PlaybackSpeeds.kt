package com.ytlite.player.playback

import java.util.Locale
import kotlin.math.abs

object PlaybackSpeeds {
    val OPTIONS = listOf(0.5f, 0.75f, 1f, 1.25f, 1.5f, 2f, 3f, 5f, 8f)

    const val MIN = 0.5f
    const val MAX = 8f

    fun coerce(speed: Float): Float = speed.coerceIn(MIN, MAX)

    fun nearest(speed: Float): Float =
        OPTIONS.minByOrNull { abs(it - speed) } ?: DEFAULT

    fun formatLabel(speed: Float): String {
        val normalized = nearest(speed)
        return if (normalized % 1f == 0f) {
            "${normalized.toInt()}x"
        } else {
            "${trimFloat(normalized)}x"
        }
    }

    private fun trimFloat(value: Float): String =
        String.format(Locale.US, "%.2f", value)
            .trimEnd('0')
            .trimEnd('.')

    const val DEFAULT = 1f
}
