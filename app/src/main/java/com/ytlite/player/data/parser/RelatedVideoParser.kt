package com.ytlite.player.data.parser

import android.util.Log
import com.ytlite.player.data.model.VideoItem
import org.json.JSONArray
import org.json.JSONObject
import java.util.ArrayDeque

object RelatedVideoParser {

    private const val TAG = "RelatedVideoParser"
    private const val MAX_NODES = 8_000

    private val VIDEO_RENDERER_KEYS = setOf(
        "videoRenderer",
        "gridVideoRenderer",
        "compactVideoRenderer",
    )

    fun parse(response: JSONObject): List<VideoItem> {
        return try {
            val videos = LinkedHashMap<String, VideoItem>()
            var nodesVisited = 0
            val queue = ArrayDeque<Any>()
            queue.add(response)

            while (queue.isNotEmpty() && nodesVisited < MAX_NODES) {
                when (val node = queue.removeFirst()) {
                    is JSONObject -> {
                        nodesVisited++
                        if (AdContentFilter.isAdNode(node)) continue
                        extractVideoFromRenderer(node)?.let { video ->
                            videos.putIfAbsent(video.videoId, video)
                        }
                        val keys = node.keys()
                        while (keys.hasNext()) {
                            when (val value = node.opt(keys.next())) {
                                is JSONObject, is JSONArray -> queue.add(value)
                            }
                        }
                    }
                    is JSONArray -> {
                        for (index in 0 until node.length()) {
                            when (val value = node.opt(index)) {
                                is JSONObject, is JSONArray -> queue.add(value)
                            }
                        }
                    }
                }
            }
            Log.d(TAG, "parse: mapped ${videos.size} related videos")
            videos.values.toList()
        } catch (e: Exception) {
            Log.e(TAG, "parse failed", e)
            emptyList()
        }
    }

    fun parseFromJsExtract(message: JSONObject): List<VideoItem> {
        val envelope = message.optJSONObject("data") ?: return emptyList()
        if (!envelope.optBoolean("success", false)) return emptyList()
        val payload = envelope.optJSONObject("data") ?: return emptyList()

        payload.optJSONArray("related")?.let { array ->
            val parsed = parseJsRelatedArray(array)
            if (parsed.isNotEmpty()) return parsed
        }
        payload.optJSONArray("watchNext")?.let { array ->
            val parsed = parseJsRelatedArray(array)
            if (parsed.isNotEmpty()) return parsed
        }
        return emptyList()
    }

    private fun parseJsRelatedArray(array: JSONArray): List<VideoItem> {
        val videos = ArrayList<VideoItem>(array.length())
        for (index in 0 until array.length()) {
            val item = array.optJSONObject(index) ?: continue
            val type = item.optString("type")
            if (AdContentFilter.isAdRendererKey(type) || type.contains("ad", ignoreCase = true)) continue
            val data = item.optJSONObject("data") ?: item
            mapJsItem(data)?.let { videos.add(it) }
        }
        return videos.distinctBy { it.videoId }
    }

    private fun mapJsItem(data: JSONObject): VideoItem? {
        val videoId = data.optString("videoId")
        if (videoId.isBlank()) return null
        val title = data.optString("title")
        if (title.isBlank()) return null
        val thumbnailUrl = pickThumbnailUrl(data.optJSONArray("thumbnails"))
            ?: "https://i.ytimg.com/vi/$videoId/hqdefault.jpg"
        return VideoItem(
            videoId = videoId,
            title = title,
            channelName = data.optString("author").ifBlank { "Unknown" },
            channelId = data.optString("channelId").takeIf { it.isNotBlank() },
            thumbnailUrl = thumbnailUrl,
            durationText = data.optString("lengthText").takeIf { it.isNotBlank() },
            viewCountText = data.optString("shortViewCountText")
                .ifBlank { data.optString("viewCountText").takeIf { v -> v.isNotBlank() } },
            publishedTimeText = data.optString("publishedTime").takeIf { it.isNotBlank() },
        )
    }

    private fun extractVideoFromRenderer(node: JSONObject): VideoItem? {
        for (key in VIDEO_RENDERER_KEYS) {
            node.optJSONObject(key)?.let { renderer ->
                return mapRenderer(renderer)
            }
        }
        return null
    }

    private fun mapRenderer(renderer: JSONObject): VideoItem? {
        val videoId = renderer.optString("videoId")
        if (videoId.isBlank()) return null
        val title = extractText(renderer.optJSONObject("title"))
        if (title.isBlank()) return null
        val channelName = extractText(renderer.optJSONObject("ownerText"))
            .ifBlank { extractText(renderer.optJSONObject("shortBylineText")) }
            .ifBlank { "Unknown" }
        val channelId = renderer.optJSONObject("longBylineText")
            ?.optJSONArray("runs")
            ?.optJSONObject(0)
            ?.optJSONObject("navigationEndpoint")
            ?.optJSONObject("browseEndpoint")
            ?.optString("browseId")
            ?.takeIf { it.isNotBlank() }
        val thumbnailUrl = renderer.optJSONObject("thumbnail")
            ?.optJSONArray("thumbnails")
            ?.let { pickThumbnailUrl(it) }
            ?: "https://i.ytimg.com/vi/$videoId/hqdefault.jpg"
        return VideoItem(
            videoId = videoId,
            title = title,
            channelName = channelName,
            channelId = channelId,
            thumbnailUrl = thumbnailUrl,
            durationText = extractText(renderer.optJSONObject("lengthText")).takeIf { it.isNotBlank() },
            viewCountText = extractText(renderer.optJSONObject("shortViewCountText"))
                .ifBlank { extractText(renderer.optJSONObject("viewCountText")) }
                .takeIf { it.isNotBlank() },
            publishedTimeText = extractText(renderer.optJSONObject("publishedTimeText")).takeIf { it.isNotBlank() },
        )
    }

    private fun extractText(textObject: JSONObject?): String {
        if (textObject == null) return ""
        textObject.optString("simpleText").takeIf { it.isNotBlank() }?.let { return it }
        val runs = textObject.optJSONArray("runs") ?: return ""
        return buildString {
            for (index in 0 until runs.length()) {
                append(runs.optJSONObject(index)?.optString("text").orEmpty())
            }
        }.trim()
    }

    private fun pickThumbnailUrl(thumbnails: JSONArray?): String? {
        if (thumbnails == null || thumbnails.length() == 0) return null
        return thumbnails.optJSONObject(thumbnails.length() - 1)?.optString("url")?.takeIf { it.isNotBlank() }
    }
}
