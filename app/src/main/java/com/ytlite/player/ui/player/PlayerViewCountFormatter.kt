package com.ytlite.player.ui.player

import java.text.NumberFormat
import java.util.Locale

fun formatPlayerViewCount(count: Long): String {
    if (count <= 0L) return ""
    return when {
        count >= 1_000_000_000 -> formatCompact(count, 1_000_000_000, "B")
        count >= 1_000_000 -> formatCompact(count, 1_000_000, "M")
        count >= 1_000 -> formatCompact(count, 1_000, "K")
        else -> NumberFormat.getNumberInstance(Locale.getDefault()).format(count)
    }
}

private fun formatCompact(count: Long, divisor: Long, suffix: String): String {
    val value = count.toDouble() / divisor
    val formatted = if (value >= 100) {
        "%.0f".format(Locale.US, value)
    } else if (value >= 10) {
        "%.0f".format(Locale.US, value)
    } else {
        "%.1f".format(Locale.US, value).trimEnd('0').trimEnd('.')
    }
    return "$formatted$suffix"
}
