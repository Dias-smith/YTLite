package com.ytlite.player.ui.player

import org.junit.Assert.assertEquals
import org.junit.Test

class PlayerViewCountFormatterTest {

    @Test
    fun formatPlayerViewCount_usesCompactSuffixes() {
        assertEquals("999", formatPlayerViewCount(999))
        assertEquals("12K", formatPlayerViewCount(12_345))
        assertEquals("167K", formatPlayerViewCount(167_000))
        assertEquals("1.2M", formatPlayerViewCount(1_234_567))
    }

    @Test
    fun formatPlayerViewCount_zeroIsEmpty() {
        assertEquals("", formatPlayerViewCount(0))
    }
}
