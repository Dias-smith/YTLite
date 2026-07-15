package com.ytlite.player.playback

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PlaybackCachePolicyTest {

    @Test
    fun isCacheableDuration_allowsUnknownAndShort() {
        assertTrue(PlaybackCachePolicy.isCacheableDuration(null))
        assertTrue(PlaybackCachePolicy.isCacheableDuration(0L))
        assertTrue(PlaybackCachePolicy.isCacheableDuration(PlaybackCachePolicy.MaxCacheableDurationMs))
    }

    @Test
    fun isCacheableDuration_rejectsOverThirtyMinutes() {
        assertFalse(
            PlaybackCachePolicy.isCacheableDuration(PlaybackCachePolicy.MaxCacheableDurationMs + 1L),
        )
    }

    @Test
    fun cacheKey_includesItagWhenPresent() {
        assertEquals("abc:18", PlaybackCachePolicy.cacheKey("abc", 18))
        assertEquals("abc", PlaybackCachePolicy.cacheKey("abc", null))
    }
}
