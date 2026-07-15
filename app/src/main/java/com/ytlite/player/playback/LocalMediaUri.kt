package com.ytlite.player.playback

import com.ytlite.player.data.model.StreamFormatIds

fun isLocalMediaUri(url: String): Boolean {
    val lower = url.lowercase()
    return lower.startsWith("file:") || lower.startsWith("content:")
}

fun isLocalAudioPlayback(url: String, itag: Int?): Boolean {
    if (!isLocalMediaUri(url)) return false
    if (itag != null && StreamFormatIds.isAudioOnlyItag(itag)) return true
    val lower = url.lowercase()
    return lower.contains(".m4a") ||
        lower.contains(".mp3") ||
        lower.contains(".aac") ||
        lower.contains(".opus") ||
        lower.contains(".ogg")
}

fun NowPlaying.isLocalAudioPlayback(): Boolean =
    isLocalAudioPlayback(streamUrl, itag)
