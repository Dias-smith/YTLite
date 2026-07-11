package com.ytlite.player.data.parser

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class VttLyricsParserTest {

    @Test
    fun parse_extractsLyricLinesWithTimestamps() {
        val vtt = """
            WEBVTT

            00:00:01.000 --> 00:00:04.000
            Hello world

            00:00:05.500 --> 00:00:08.000
            Second <c>line</c>
        """.trimIndent()

        val lines = VttLyricsParser.parse(vtt)

        assertEquals(2, lines.size)
        assertEquals("Hello world", lines[0].text)
        assertEquals(1000L, lines[0].startMs)
        assertEquals("Second line", lines[1].text)
        assertEquals(5500L, lines[1].startMs)
    }

    @Test
    fun parse_emptyInput_returnsEmptyList() {
        assertTrue(VttLyricsParser.parse("WEBVTT\n").isEmpty())
    }
}
