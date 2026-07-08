package com.ytlite.player.ui.player

import com.ytlite.player.data.model.StreamFormat

object PlaybackFormatSelector {

    private const val PREFERRED_ITAG = 18

    fun selectVideoFormat(formats: List<StreamFormat>): StreamFormat? {
        formats.firstOrNull { it.itag == PREFERRED_ITAG && it.hasAudio && it.hasVideo }?.let { return it }

        formats
            .filter { it.hasAudio && it.hasVideo }
            .maxByOrNull { it.height }
            ?.let { return it }

        return formats.firstOrNull { it.hasAudio && it.hasVideo }
            ?: formats.firstOrNull { it.hasVideo }
    }

    fun selectAudioFormat(formats: List<StreamFormat>): StreamFormat? {
        formats
            .filter { it.hasAudio && !it.hasVideo }
            .maxByOrNull { it.height }
            ?.let { return it }

        return formats.firstOrNull { it.hasAudio }
    }

    fun selectFormat(formats: List<StreamFormat>, audioOnly: Boolean): StreamFormat? =
        if (audioOnly) selectAudioFormat(formats) else selectVideoFormat(formats)
}
