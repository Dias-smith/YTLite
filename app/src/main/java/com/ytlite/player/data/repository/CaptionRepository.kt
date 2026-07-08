package com.ytlite.player.data.repository

import com.ytlite.player.data.model.CaptionTrack
import com.ytlite.player.data.network.YouTubeHttpClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class CaptionRepository(
    private val httpClient: YouTubeHttpClient = YouTubeHttpClient.getInstance(),
) {

    suspend fun fetchVtt(track: CaptionTrack): String? = withContext(Dispatchers.IO) {
        val url = buildVttUrl(track.baseUrl)
        runCatching {
            val result = httpClient.request(
                url = url,
                method = "GET",
                headers = emptyMap(),
                body = null,
            )
            if (result.success && !result.result.isNullOrBlank()) {
                result.result
            } else {
                null
            }
        }.getOrNull()
    }

    fun pickDefaultTrack(tracks: List<CaptionTrack>, preferredLanguage: String = "en"): CaptionTrack? {
        if (tracks.isEmpty()) return null
        tracks.firstOrNull { it.languageCode.equals(preferredLanguage, ignoreCase = true) }?.let { return it }
        tracks.firstOrNull { it.languageCode.startsWith(preferredLanguage, ignoreCase = true) }?.let { return it }
        return tracks.first()
    }

    private fun buildVttUrl(baseUrl: String): String {
        val separator = if (baseUrl.contains("?")) "&" else "?"
        return if (baseUrl.contains("fmt=")) {
            baseUrl
        } else {
            "${baseUrl}${separator}fmt=vtt"
        }
    }

    companion object {
        @Volatile
        private var instance: CaptionRepository? = null

        fun getInstance(): CaptionRepository =
            instance ?: synchronized(this) {
                instance ?: CaptionRepository().also { instance = it }
            }
    }
}
