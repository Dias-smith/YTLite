package com.ytlite.player.ui.player

import com.ytlite.player.data.model.StreamFormat

object PlaybackFormatSelector {

    /** Progressive muxed preference: higher quality first, then 18. */
    private val PREFERRED_VIDEO_ITAGS = listOf(37, 22, 18)

    /** AAC audio-only preference. */
    private val PREFERRED_AUDIO_ITAGS = listOf(140, 141, 139)

    /**
     * Download / picker sort: preferred itags first (37→22→18→141→140→139),
     * then remaining formats (video muxed by height, then audio, then other).
     */
    val PREFERRED_DOWNLOAD_ITAG_ORDER = listOf(37, 22, 18, 141, 140, 139)

    fun selectVideoFormat(formats: List<StreamFormat>): StreamFormat? {
        for (itag in PREFERRED_VIDEO_ITAGS) {
            formats.firstOrNull { it.itag == itag && it.hasAudio && it.hasVideo }?.let { return it }
        }

        formats
            .filter { it.hasAudio && it.hasVideo }
            .maxByOrNull { it.height }
            ?.let { return it }

        return formats.firstOrNull { it.hasAudio && it.hasVideo }
            ?: formats.firstOrNull { it.hasVideo }
    }

    fun selectAudioFormat(formats: List<StreamFormat>): StreamFormat? {
        for (itag in PREFERRED_AUDIO_ITAGS) {
            formats.firstOrNull { it.itag == itag && it.hasAudio && !it.hasVideo }?.let { return it }
        }

        return formats
            .filter { it.hasAudio && !it.hasVideo }
            .maxByOrNull { it.itag }
    }

    fun selectFormat(formats: List<StreamFormat>, audioOnly: Boolean): StreamFormat? =
        if (audioOnly) selectAudioFormat(formats) else selectVideoFormat(formats)

    fun selectByItag(formats: List<StreamFormat>, itag: Int): StreamFormat? =
        formats.firstOrNull { it.itag == itag }

    fun listVideoFormats(formats: List<StreamFormat>): List<StreamFormat> =
        formats
            .filter { it.hasVideo }
            .distinctBy { it.itag }
            .sortedByDescending { it.height }

    fun sortForDownload(formats: List<StreamFormat>): List<StreamFormat> {
        val preferredIndex = PREFERRED_DOWNLOAD_ITAG_ORDER.withIndex()
            .associate { (index, itag) -> itag to index }
        return formats
            .distinctBy { it.itag }
            .sortedWith(
                compareBy<StreamFormat> { preferredIndex[it.itag] ?: Int.MAX_VALUE }
                    .thenByDescending { it.hasVideo && it.hasAudio }
                    .thenByDescending { it.height }
                    .thenByDescending { it.hasAudio },
            )
    }
}
