package com.ytlite.player.ui.player

import com.ytlite.player.data.extractor.ExtractorRemoteConfigStore
import com.ytlite.player.data.model.StreamFormat

object PlaybackFormatSelector {

    /** Progressive muxed preference; overridden by remote extractor manifest when present. */
    private fun preferredVideoItags(): List<Int> {
        val remote = ExtractorRemoteConfigStore.current().preferItags
        return remote.ifEmpty { listOf(18, 22, 37) }
    }

    /** AAC audio-only preference. */
    private val PREFERRED_AUDIO_ITAGS = listOf(140, 141, 139)

    /**
     * Download / picker sort: preferred itags first, then remaining formats.
     */
    val PREFERRED_DOWNLOAD_ITAG_ORDER: List<Int>
        get() = preferredVideoItags() + listOf(141, 140, 139)

    fun selectVideoFormat(formats: List<StreamFormat>): StreamFormat? {
        for (itag in preferredVideoItags()) {
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
