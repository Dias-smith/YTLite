package com.ytlite.player.data.parser

import android.util.Log
import com.ytlite.player.data.model.FeedPage
import com.ytlite.player.data.model.VideoItem
import com.ytlite.player.data.youtube.YoutubeDiagnostics
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
            var lockupCount = 0
            var videoRendererCount = 0
            var continuationVmCount = 0
            val queue = ArrayDeque<Any>()
            collectParseRoots(response).forEach { queue.add(it) }

            while (queue.isNotEmpty() && nodesVisited < MAX_NODES) {
                when (val node = queue.removeFirst()) {
                    is JSONObject -> {
                        nodesVisited++
                        if (node.has("lockupViewModel")) lockupCount++
                        if (VIDEO_RENDERER_KEYS.any { node.has(it) }) videoRendererCount++
                        if (node.has("continuationItemViewModel")) continuationVmCount++
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
                YoutubeDiagnostics.w(
                    TAG,
                    "parse empty: lockupViewModel=$lockupCount videoRenderer=$videoRendererCount " +
                        "continuationItemViewModel=$continuationVmCount nodesVisited=$nodesVisited " +
                        "histogram=${debugRendererHistogram(response)}",
                )
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

    private fun collectParseRoots(response: JSONObject): List<Any> {
        val roots = mutableListOf<Any>(response)
        for (actionsKey in ACTION_ARRAY_KEYS) {
            val actions = response.optJSONArray(actionsKey) ?: continue
            for (index in 0 until actions.length()) {
                val action = actions.optJSONObject(index) ?: continue
                for (commandKey in CONTINUATION_COMMAND_KEYS) {
                    val command = action.optJSONObject(commandKey) ?: continue
                    val items = command.optJSONArray("continuationItems") ?: continue
                    for (itemIndex in 0 until items.length()) {
                        items.opt(itemIndex)?.let { roots.add(it) }
                    }
                }
            }
        }
        return roots
    }

    private fun extractVideoFromRenderer(node: JSONObject): VideoItem? {
        node.optJSONObject("lockupViewModel")?.let { lockup ->
            LockupViewModelParser.parseVideo(lockup)?.let { return it }
        }

        node.optJSONObject("richItemRenderer")
            ?.optJSONObject("content")
            ?.let { content -> extractVideoFromRenderer(content)?.let { return it } }

        node.optJSONObject("reelItemRenderer")?.let { reel ->
            val videoId = reel.optJSONObject("navigationEndpoint")
                ?.optJSONObject("reelWatchEndpoint")
                ?.optString("videoId")
                ?.takeIf { it.isNotBlank() }
            if (videoId != null) {
                val title = extractText(reel.optJSONObject("headline")) ?: "Short"
                val channelName = extractText(reel.optJSONObject("navigationEndpoint")
                    ?.optJSONObject("reelWatchEndpoint")
                    ?.optJSONObject("overlay")
                    ?.optJSONObject("reelPlayerOverlayRenderer")
                    ?.optJSONObject("reelPlayerNavigationModel")
                    ?.optJSONObject("title"))
                    ?: "Unknown"
                return VideoItem(
                    videoId = videoId,
                    title = title,
                    channelName = channelName,
                    channelId = null,
                    thumbnailUrl = pickThumbnailUrl(reel.optJSONObject("thumbnail"))
                        ?: "https://i.ytimg.com/img/no_thumbnail.jpg",
                    durationText = null,
                    viewCountText = extractText(reel.optJSONObject("viewCountText")),
                    publishedTimeText = null,
                )
            }
        }

        for (key in VIDEO_RENDERER_KEYS) {
            if (!node.has(key)) continue
            val renderer = node.optJSONObject(key) ?: continue
            return mapRenderer(renderer)
        }

        node.optJSONObject("videoCardRenderer")?.let { card ->
            return mapRenderer(card)
        }

        return null
    }

    /** Debug helper: top renderer/viewModel keys found in a response tree. */
    fun debugRendererHistogram(response: JSONObject, limit: Int = 12): String {
        val counts = linkedMapOf<String, Int>()
        val queue = ArrayDeque<Any>()
        queue.add(response)
        var visited = 0
        while (queue.isNotEmpty() && visited < 2_000) {
            when (val node = queue.removeFirst()) {
                is JSONObject -> {
                    visited++
                    val keys = node.keys()
                    while (keys.hasNext()) {
                        val key = keys.next()
                        if (key.endsWith("Renderer") || key.endsWith("ViewModel")) {
                            counts[key] = (counts[key] ?: 0) + 1
                        }
                        when (val value = node.opt(key)) {
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
        return counts.entries
            .sortedByDescending { it.value }
            .take(limit)
            .joinToString { "${it.key}=${it.value}" }
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
                    if (node.has("continuationItemViewModel")) {
                        val token = node.optJSONObject("continuationItemViewModel")
                            ?.optJSONObject("continuationCommand")
                            ?.optJSONObject("innertubeCommand")
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

    private val ACTION_ARRAY_KEYS = listOf(
        "onResponseReceivedActions",
        "onResponseReceivedCommands",
    )

    private val CONTINUATION_COMMAND_KEYS = listOf(
        "appendContinuationItemsAction",
        "reloadContinuationItemsCommand",
    )
}
