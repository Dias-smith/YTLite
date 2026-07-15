package com.ytlite.player.data.js

import android.util.Log
import com.ytlite.player.data.model.StreamFormat
import com.ytlite.player.data.model.VideoPlayback
import com.ytlite.player.data.network.YouTubeHttpClient
import org.json.JSONArray
import org.json.JSONObject

/**
 * When InnerTube clients return UNPLAYABLE, scrape `ytInitialPlayerResponse` from the
 * public watch / shorts HTML page (often still exposes progressive itag 18 with direct urls).
 */
object WatchPagePlayerFallback {

    private const val TAG = "WatchPagePlayerFallback"
    private val httpClient: YouTubeHttpClient = YouTubeHttpClient.getInstance()

    private val pageUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 " +
            "(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    fun extract(videoId: String): VideoPlayback? {
        val id = videoId.trim()
        if (id.isEmpty()) return null
        val pages = listOf(
            "https://www.youtube.com/watch?v=$id",
            "https://www.youtube.com/shorts/$id",
            "https://m.youtube.com/watch?v=$id",
        )
        for (pageUrl in pages) {
            runCatching {
                val html = fetchHtml(pageUrl) ?: return@runCatching null
                val player = extractPlayerResponse(html) ?: return@runCatching null
                return mapPlayerResponse(player, id)
            }.onFailure { error ->
                Log.w(TAG, "fallback failed for $pageUrl videoId=$id", error)
            }
        }
        return null
    }

    private fun fetchHtml(url: String): String? {
        val result = httpClient.request(
            url = url,
            method = "GET",
            headers = mapOf(
                "User-Agent" to pageUserAgent,
                "Accept-Language" to "en-US,en;q=0.9",
                "Accept" to "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            ),
            body = null,
        )
        if (!result.success || result.result.isNullOrBlank()) {
            Log.w(TAG, "page fetch failed code=${result.errCode} msg=${result.errMsg}")
            return null
        }
        return result.result
    }

    private fun extractPlayerResponse(html: String): JSONObject? {
        val marker = "ytInitialPlayerResponse = "
        var searchFrom = 0
        while (true) {
            val markerIndex = html.indexOf(marker, searchFrom)
            if (markerIndex < 0) return null
            var cursor = markerIndex + marker.length
            while (cursor < html.length && html[cursor].isWhitespace()) cursor++
            if (html.startsWith("null", cursor)) {
                searchFrom = cursor + 4
                continue
            }
            if (cursor >= html.length || html[cursor] != '{') {
                searchFrom = cursor + 1
                continue
            }
            val jsonText = extractBalancedObject(html, cursor)
            if (jsonText == null) {
                searchFrom = cursor + 1
                continue
            }
            runCatching {
                val obj = JSONObject(jsonText)
                if (obj.has("videoDetails") || obj.has("streamingData")) {
                    return obj
                }
            }.onFailure { Log.w(TAG, "JSON parse failed", it) }
            searchFrom = cursor + 1
        }
    }

    private fun extractBalancedObject(text: String, start: Int): String? {
        var depth = 0
        var inString = false
        var escaped = false
        for (i in start until text.length) {
            val ch = text[i]
            if (inString) {
                when {
                    escaped -> escaped = false
                    ch == '\\' -> escaped = true
                    ch == '"' -> inString = false
                }
            } else {
                when (ch) {
                    '"' -> inString = true
                    '{' -> depth++
                    '}' -> {
                        depth--
                        if (depth == 0) {
                            return text.substring(start, i + 1)
                        }
                    }
                }
            }
        }
        return null
    }

    private fun mapPlayerResponse(player: JSONObject, fallbackVideoId: String): VideoPlayback? {
        val status = player.optJSONObject("playabilityStatus")
            ?.optString("status")
            .orEmpty()
            .uppercase()
        if (status.isNotEmpty() && status != "OK") {
            Log.w(TAG, "page playability=$status reason=${player.optJSONObject("playabilityStatus")?.optString("reason")}")
            return null
        }

        val streaming = player.optJSONObject("streamingData") ?: JSONObject()
        val formats = ArrayList<StreamFormat>()
        appendFormats(streaming.optJSONArray("formats"), formats)
        appendFormats(streaming.optJSONArray("adaptiveFormats"), formats)
        if (formats.isEmpty()) {
            Log.w(TAG, "page has no formats with url")
            return null
        }

        val details = player.optJSONObject("videoDetails") ?: JSONObject()
        val videoId = details.optString("videoId").ifBlank { fallbackVideoId }
        val channelName = details.optString("author").ifBlank {
            player.optJSONObject("microformat")
                ?.optJSONObject("playerMicroformatRenderer")
                ?.optString("ownerChannelName")
                .orEmpty()
        }
        return VideoPlayback(
            videoId = videoId,
            title = details.optString("title").ifBlank { videoId },
            description = details.optString("shortDescription"),
            channelName = channelName,
            channelId = details.optString("channelId"),
            formats = formats,
            durationSeconds = details.optString("lengthSeconds").toLongOrNull() ?: 0L,
            viewCount = details.optString("viewCount").toLongOrNull() ?: 0L,
            captionTracks = emptyList(),
        )
    }

    private fun appendFormats(array: JSONArray?, out: MutableList<StreamFormat>) {
        if (array == null) return
        for (index in 0 until array.length()) {
            val item = array.optJSONObject(index) ?: continue
            val url = item.optString("url")
            if (url.isBlank()) continue
            val mime = item.optString("mimeType").ifBlank { item.optString("type") }
            val codecs = mimeCodecs(mime)
            val hasAudio = codecs.any { it.startsWith("mp4a") || it.startsWith("opus") || it.startsWith("aac") } ||
                mime.contains("audio/") ||
                item.has("audioQuality") ||
                item.has("audioSampleRate")
            val width = item.optInt("width")
            val height = item.optInt("height")
            val hasVideo = codecs.any {
                it.startsWith("avc") || it.startsWith("vp9") || it.startsWith("av01") || it.startsWith("hev")
            } || mime.contains("video/") || width > 0 || height > 0
            out.add(
                StreamFormat(
                    itag = item.optInt("itag"),
                    width = width,
                    height = height,
                    hasAudio = hasAudio,
                    hasVideo = hasVideo,
                    url = url,
                    mimeType = mime,
                    contentLengthBytes = item.optString("contentLength").toLongOrNull() ?: 0L,
                    bitrateBps = item.optLong("bitrate"),
                ),
            )
        }
    }

    private fun mimeCodecs(mime: String): List<String> {
        val start = mime.indexOf("codecs=\"")
        if (start < 0) return emptyList()
        val from = start + "codecs=\"".length
        val end = mime.indexOf('"', from)
        if (end < 0) return emptyList()
        return mime.substring(from, end)
            .split(',')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
    }
}
