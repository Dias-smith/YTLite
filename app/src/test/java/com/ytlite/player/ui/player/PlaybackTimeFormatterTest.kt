package com.ytlite.player.ui.player

import org.junit.Assert.assertEquals
import org.junit.Test

class PlaybackTimeFormatterTest {

    @Test
    fun formatPlaybackTime_underOneHour_usesMinutesAndSeconds() {
        assertEquals("0:00", formatPlaybackTime(0))
        assertEquals("0:34", formatPlaybackTime(34_000))
        assertEquals("3:58", formatPlaybackTime(238_000))
        assertEquals("59:59", formatPlaybackTime(3_599_000))
    }

    @Test
    fun formatPlaybackTime_oneHourOrMore_includesHours() {
        assertEquals("1:00:00", formatPlaybackTime(3_600_000))
        assertEquals("3:17:03", formatPlaybackTime(11_823_000))
    }
}
