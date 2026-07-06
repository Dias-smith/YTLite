package com.ytlite.player.data.parser

import android.util.Log
import com.ytlite.player.data.model.FeedPage
import com.ytlite.player.data.model.VideoItem
import org.json.JSONArray
import org.json.JSONObject
import java.util.ArrayDeque

object FeedParser {

    private const val TAG = "FeedParser"
    private const val MAX_NODES = 8_000

    private val AD_RENDERER_KEYS = setOf(
        "adVideoRenderer",
        "promotedSparklesWebRenderer",
        "displayAdRenderer",
        "promotedVideoRenderer",
        "compactPromotedVideoRenderer",
    )

    private val VIDEO_RENDERER_KEYS = setOf(
        "videoRenderer",
        "gridVideoRenderer",
        "compactVideoRenderer",
    )

    fun parse(response: JSONObject): FeedPage? {
        return try {
            val videos = LinkedHashMap<String, VideoItem>()
            var nodesVisited = 0
            val queue = ArrayDeque<Any>()
            queue.add(response)

            while (queue.isNotEmpty() && nodesVisited < MAX_NODES) {
                when (val node = queue.removeFirst()) {
                    is JSONObject -> {
                        nodesVisited++
                        if (isAdNode(node)) continue
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

            val continuation = extractContinuation(response)
            if (videos.isEmpty()) {
                Log.w(TAG, "parse: no videos found, continuation=${continuation != null}")
                return null
            }
            Log.d(TAG, "parse: mapped ${videos.size} videos")
            FeedPage(
                videos = videos.values.toList(),
                continuation = continuation,
            )
        } catch (e: Exception) {
            Log.e(TAG, "parse failed", e)
            null
        }
    }

    private fun isAdNode(node: JSONObject): Boolean {
        val type = node.optString("type")
        if (type.equals("ad", ignoreCase = true)) return true
        val render = node.optString("render")
        if (render.equals("promoted", ignoreCase = true)) return true
        return AD_RENDERER_KEYS.any { node.has(it) }
    }

    private fun extractVideoFromRenderer(node: JSONObject): VideoItem? {
        for (key in VIDEO_RENDERER_KEYS) {
            if (!node.has(key)) continue
            val renderer = node.optJSONObject(key) ?: continue
            return mapRenderer(renderer)
        }
        return null
    }

    private fun mapRenderer(renderer: JSONObject): VideoItem? {
        val videoId = renderer.optString("videoId")
        if (videoId.isBlank()) return null

        val title = extractText(renderer.optJSONObject("title"))
            ?: extractText(renderer.optJSONObject("headline"))
        if (title.isNullOrBlank()) return null

        val thumbnailUrl = pickThumbnailUrl(renderer.optJSONObject("thumbnail"))
            ?: pickThumbnailUrl(renderer.optJSONObject("thumbnails"))
            ?: "https://i.ytimg.com/img/no_thumbnail.jpg"

        val channelName = extractText(renderer.optJSONObject("ownerText"))
            ?: extractText(renderer.optJSONObject("shortBylineText"))
            ?: extractText(renderer.optJSONObject("longBylineText"))
            ?: "Unknown"

        val channelId = renderer.optJSONObject("ownerText")
            ?.optJSONArray("runs")
            ?.optJSONObject(0)
            ?.optJSONObject("navigationEndpoint")
            ?.optJSONObject("browseEndpoint")
            ?.optString("browseId")
            ?.takeIf { it.isNotBlank() }

        return VideoItem(
            videoId = videoId,
            title = title,
            channelName = channelName,
            channelId = channelId,
            thumbnailUrl = thumbnailUrl,
            durationText = extractText(renderer.optJSONObject("lengthText")),
            viewCountText = extractText(renderer.optJSONObject("shortViewCountText"))
                ?: extractText(renderer.optJSONObject("viewCountText")),
            publishedTimeText = extractText(renderer.optJSONObject("publishedTimeText")),
        )
    }

    private fun pickThumbnailUrl(thumbnail: JSONObject?): String? {
        val thumbnails = thumbnail?.optJSONArray("thumbnails") ?: return null
        if (thumbnails.length() == 0) return null
        return thumbnails.optJSONObject(thumbnails.length() - 1)
            ?.optString("url")
            ?.takeIf { it.isNotBlank() }
    }

    private fun extractText(textObject: JSONObject?): String? {
        if (textObject == null) return null
        val simple = textObject.optString("simpleText")
        if (simple.isNotBlank()) return simple

        val runs = textObject.optJSONArray("runs") ?: return null
        val builder = StringBuilder()
        for (index in 0 until runs.length()) {
            builder.append(runs.optJSONObject(index)?.optString("text").orEmpty())
        }
        return builder.toString().takeIf { it.isNotBlank() }
    }

    private fun extractContinuation(response: JSONObject): String? {
        var found: String? = null
        val queue = ArrayDeque<Any>()
        queue.add(response)
        var nodesVisited = 0

        while (queue.isNotEmpty() && nodesVisited < MAX_NODES) {
            when (val node = queue.removeFirst()) {
                is JSONObject -> {
                    nodesVisited++
                    if (node.has("continuationItemRenderer")) {
                        val token = node.optJSONObject("continuationItemRenderer")
                            ?.optJSONObject("continuationEndpoint")
                            ?.optJSONObject("continuationCommand")
                            ?.optString("token")
                        if (!token.isNullOrBlank()) {
                            found = token
                            return found
                        }
                    }
                    val continuationEndpoint = node.optJSONObject("continuationEndpoint")
                    val token = continuationEndpoint
                        ?.optJSONObject("continuationCommand")
                        ?.optString("token")
                    if (!token.isNullOrBlank() && node.has("continuationItemRenderer").not()) {
                        // Prefer explicit continuation items; keep scanning.
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
        return found
    }
}
