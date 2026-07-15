package com.ytlite.player.ui.player

import com.ytlite.player.data.model.StreamFormat
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PlaybackFormatSelectorTest {

    @Test
    fun selectVideoFormat_prefers37Then22Then18() {
        val formats = listOf(
            format(itag = 140, hasAudio = true, hasVideo = false, height = 0),
            format(itag = 18, hasAudio = true, hasVideo = true, height = 360),
            format(itag = 22, hasAudio = true, hasVideo = true, height = 720),
            format(itag = 37, hasAudio = true, hasVideo = true, height = 1080),
        )
        assertEquals(37, PlaybackFormatSelector.selectVideoFormat(formats)?.itag)

        val without37 = formats.filter { it.itag != 37 }
        assertEquals(22, PlaybackFormatSelector.selectVideoFormat(without37)?.itag)

        val only18 = formats.filter { it.itag == 18 || it.itag == 140 }
        assertEquals(18, PlaybackFormatSelector.selectVideoFormat(only18)?.itag)
    }

    @Test
    fun selectAudioFormat_prefers140Then141Then139() {
        val formats = listOf(
            format(itag = 139, hasAudio = true, hasVideo = false, height = 0),
            format(itag = 141, hasAudio = true, hasVideo = false, height = 0),
            format(itag = 140, hasAudio = true, hasVideo = false, height = 0),
            format(itag = 18, hasAudio = true, hasVideo = true, height = 360),
        )
        assertEquals(140, PlaybackFormatSelector.selectAudioFormat(formats)?.itag)
    }

    @Test
    fun sortForDownload_putsPreferredItagsFirst() {
        val formats = listOf(
            format(itag = 299, hasAudio = false, hasVideo = true, height = 1080),
            format(itag = 140, hasAudio = true, hasVideo = false, height = 0),
            format(itag = 18, hasAudio = true, hasVideo = true, height = 360),
            format(itag = 22, hasAudio = true, hasVideo = true, height = 720),
        )
        val sorted = PlaybackFormatSelector.sortForDownload(formats).map { it.itag }
        assertEquals(listOf(22, 18, 140, 299), sorted)
    }

    @Test
    fun selectVideoFormat_returnsNullWhenEmpty() {
        assertNull(PlaybackFormatSelector.selectVideoFormat(emptyList()))
    }

    private fun format(
        itag: Int,
        hasAudio: Boolean,
        hasVideo: Boolean,
        height: Int,
    ) = StreamFormat(
        itag = itag,
        width = if (hasVideo) height * 16 / 9 else 0,
        height = height,
        hasAudio = hasAudio,
        hasVideo = hasVideo,
        url = "https://example.com/$itag",
        mimeType = if (hasVideo) "video/mp4" else "audio/mp4",
    )
}
