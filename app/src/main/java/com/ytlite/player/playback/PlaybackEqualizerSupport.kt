package com.ytlite.player.playback

object PlaybackEqualizerSupport {
    fun isEligibleStreamUrl(streamUrl: String?): Boolean {
        if (streamUrl.isNullOrBlank()) return false
        val lower = streamUrl.lowercase()
        if (lower.contains(".m3u8")) return false
        if (lower.contains("/manifest/hls")) return false
        return true
    }
}
