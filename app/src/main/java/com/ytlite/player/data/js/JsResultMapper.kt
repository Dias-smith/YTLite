package com.ytlite.player.data.js

import android.util.Log
import com.ytlite.player.data.model.FeedPage
import com.ytlite.player.data.model.VideoItem
import com.ytlite.player.data.model.StreamFormat
import com.ytlite.player.data.model.VideoPlayback
import org.json.JSONArray
import org.json.JSONObject

object JsResultMapper {

    private const val TAG = "JsResultMapper"

    private val SKIPPED_TYPES = setOf(
        "reelShelfRenderer",
        "adVideoRenderer",
        "promotedSparklesWebRenderer",
        "displayAdRenderer",
    )

    fun toFeedPage(message: JSONObject): FeedPage? {
        // createSearchMsg(r, searchApiResult) puts the SearchApi payload directly in message.data
        val payload = message.optJSONObject("data") ?: run {
            Log.w(TAG, "toFeedPage: missing data object")
            return null
        }

        if (!payload.optBoolean("success", false)) {
            Log.w(
                TAG,
                "toFeedPage: success=false code=${payload.optInt("errorCode", -1)} " +
                    "isReady=${payload.optBoolean("isReady")}",
            )
            return null
        }

        val items = payload.optJSONArray("data") ?: JSONArray()
        Log.d(TAG, "toFeedPage: raw items=${items.length()}")

        val videos = ArrayList<VideoItem>(items.length())
        for (index in 0 until items.length()) {
            val item = items.optJSONObject(index) ?: continue
            val type = item.optString("type")
            if (type in SKIPPED_TYPES || type.contains("ad", ignoreCase = true)) continue
            if (type != "compactVideoRenderer" && type != "gridVideoRenderer") {
                if (index < 3) Log.d(TAG, "skip type=$type")
                continue
            }
            val data = item.optJSONObject("data") ?: continue
            mapSearchItem(data)?.let { videos.add(it) }
        }

        val continuation = payload.optString("next").takeIf { it.isNotBlank() }
        if (videos.isEmpty()) {
            Log.w(TAG, "toFeedPage: mapped 0 videos from ${items.length()} items")
            return null
        }
        Log.d(TAG, "toFeedPage: mapped ${videos.size} videos")
        return FeedPage(
            videos = videos.distinctBy { it.videoId },
            continuation = continuation,
        )
    }

    fun toVideoPlayback(message: JSONObject): VideoPlayback? {
        val envelope = message.optJSONObject("data") ?: return null
        if (!envelope.optBoolean("success", false)) return null

        val payload = envelope.optJSONObject("data") ?: return null
        val music = payload.optJSONObject("music") ?: return null
        val videoId = music.optString("videoId")
            .ifBlank { payload.optString("url").let(::extractVideoIdFromUrl) }
        if (videoId.isBlank()) return null

        val formats = mapFormats(music.optJSONArray("formats"))
        if (formats.isEmpty()) return null

        return VideoPlayback(
            videoId = videoId,
            title = music.optString("title"),
            description = music.optString("description"),
            channelName = music.optString("uploader"),
            channelId = music.optString("channelID"),
            formats = formats,
            durationSeconds = music.optString("duration").toLongOrNull() ?: 0L,
            viewCount = music.optString("viewCount").toLongOrNull() ?: 0L,
        )
    }

    fun mapFormats(formats: JSONArray?): List<StreamFormat> {
        if (formats == null || formats.length() == 0) return emptyList()

        val mapped = (0 until formats.length()).mapNotNull { index ->
            val format = formats.optJSONObject(index) ?: return@mapNotNull null
            val url = format.optString("url")
            if (url.isBlank()) return@mapNotNull null

            val acodec = format.optString("acodec")
            val vcodec = format.optString("vcodec")
            StreamFormat(
                itag = format.optInt("itag"),
                width = format.optInt("width"),
                height = format.optInt("height"),
                hasAudio = acodec.isNotBlank(),
                hasVideo = vcodec.isNotBlank(),
                url = url,
                mimeType = format.optString("type").ifBlank { format.optString("mimeType") },
            )
        }

        return mapped.sortedWith(
            compareByDescending<StreamFormat> { it.hasVideo && it.hasAudio }
                .thenByDescending { it.height },
        )
    }

    fun playbackErrorMessage(message: JSONObject): String? {
        val envelope = message.optJSONObject("data") ?: return null
        val payload = envelope.optJSONObject("data")
        return envelope.optString("errorMsg")
            .ifBlank { envelope.optString("errorMSG") }
            .ifBlank { payload?.optString("errMsg").orEmpty() }
            .ifBlank { payload?.optString("errorMSG").orEmpty() }
            .ifBlank {
                if (payload?.optJSONObject("music") == null) {
                    "Unable to extract playable stream"
                } else {
                    ""
                }
            }
            .removePrefix("__notRetry@")
            .takeIf { it.isNotBlank() }
    }

    fun errorMessage(message: JSONObject): String? {
        val payload = message.optJSONObject("data")
        if (payload == null) {
            return message.optString("errorMsg").takeIf { it.isNotBlank() }
        }

        val errorCode = payload.optInt("errorCode", -1)
        return payload.optString("errorMsg")
            .ifBlank { payload.optString("errorMSG") }
            .ifBlank { payload.optString("errMsg") }
            .ifBlank {
                if (!payload.optBoolean("success", true) && errorCode > 0) {
                    "Search failed (HTTP $errorCode)"
                } else {
                    ""
                }
            }
            .ifBlank {
                if (!payload.optBoolean("success", true)) {
                    "YouTube search returned no results"
                } else {
                    ""
                }
            }
            .takeIf { it.isNotBlank() }
    }

    private fun mapSearchItem(data: JSONObject): VideoItem? {
        val videoId = data.optString("videoId")
        if (videoId.isBlank()) return null

        val title = data.optString("title")
        if (title.isBlank()) return null

        val thumbnailUrl = pickThumbnailUrl(data.optJSONArray("thumbnails"))
            ?: "https://i.ytimg.com/img/no_thumbnail.jpg"
        return VideoItem(
            videoId = videoId,
            title = title,
            channelName = data.optString("author").ifBlank { "Unknown" },
            channelId = null,
            thumbnailUrl = thumbnailUrl,
            durationText = data.optString("lengthText").ifBlank { null },
            viewCountText = data.optString("shortViewCountText")
                .ifBlank { data.optString("viewCountText").ifBlank { null } },
            publishedTimeText = data.optString("publishedTime").ifBlank { null },
        )
    }

    private fun pickThumbnailUrl(thumbnails: JSONArray?): String? {
        if (thumbnails == null || thumbnails.length() == 0) return null
        return thumbnails.optJSONObject(thumbnails.length() - 1)?.optString("url")?.takeIf { it.isNotBlank() }
    }

    private fun extractVideoIdFromUrl(url: String): String {
        val match = VIDEO_ID_REGEX.find(url) ?: return ""
        return match.groupValues[1]
    }

    private val VIDEO_ID_REGEX = Regex("(?:v=|/)([0-9A-Za-z_-]{11})")
}
