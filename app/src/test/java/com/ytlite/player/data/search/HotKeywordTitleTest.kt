package com.ytlite.player.data.search

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class HotKeywordTitleTest {
    @Test
    fun stripsParenthesesAndNoiseSuffix() {
        assertEquals("Song Name", HotKeywordTitle.clean("Song Name (Official Video)"))
        assertEquals("Artist - Song", HotKeywordTitle.clean("Artist - Song [Official Audio]"))
        assertEquals("Title", HotKeywordTitle.clean("Title【MV】"))
        assertEquals(
            "Artist - Song",
            HotKeywordTitle.clean("Artist - Song - Official Music Video"),
        )
        assertEquals("Foo", HotKeywordTitle.clean("Foo (feat. Bar) (Lyric Video)"))
        assertEquals("Just Title", HotKeywordTitle.clean("Just Title"))
        assertNull(HotKeywordTitle.clean("  "))
    }
}
