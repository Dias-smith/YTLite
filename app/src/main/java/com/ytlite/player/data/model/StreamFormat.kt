package com.ytlite.player.data.model

import androidx.compose.runtime.Immutable

@Immutable
data class StreamFormat(
    val itag: Int,
    val width: Int,
    val height: Int,
    val hasAudio: Boolean,
    val hasVideo: Boolean,
    val url: String,
    val mimeType: String = "",
    val contentLengthBytes: Long = 0L,
    /** Bits per second when known; used to estimate size when content length is missing. */
    val bitrateBps: Long = 0L,
)

object StreamFormatIds {
    val AUDIO_ONLY_ITAGS = setOf(139, 140, 141)

    fun isAudioOnlyItag(itag: Int): Boolean = itag in AUDIO_ONLY_ITAGS
}

fun StreamFormat.isAudioOnly(): Boolean {
    if (StreamFormatIds.isAudioOnlyItag(itag)) return hasAudio && !hasVideo
    if (!hasAudio || hasVideo) return false
    val mime = mimeType.lowercase()
    if (mime.startsWith("audio")) return true
    return width <= 0 && height <= 0
}

fun StreamFormat.resolvedContentLengthBytes(durationSeconds: Long): Long {
    if (contentLengthBytes > 0L) return contentLengthBytes
    if (bitrateBps > 0L && durationSeconds > 0L) {
        return (bitrateBps / 8L) * durationSeconds
    }
    return 0L
}
