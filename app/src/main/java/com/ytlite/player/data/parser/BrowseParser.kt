package com.ytlite.player.data.parser

import android.util.Log
import com.ytlite.player.data.model.DiscoveryType
import com.ytlite.player.data.model.SearchResultItem
import com.ytlite.player.data.model.VideoItem
import org.json.JSONArray
import org.json.JSONObject
import java.util.ArrayDeque

data class BrowseSection(
    val title: String,
    val videos: List<VideoItem> = emptyList(),
)

data class BrowseMoodItem(
    val browseId: String,
    val title: String,
    val thumbnailUrl: String?,
    val accentColorArgb: Int? = null,
)

data class BrowsePage(
    val featuredVideo: VideoItem? = null,
    val sections: List<BrowseSection> = emptyList(),
    val moodItems: List<BrowseMoodItem> = emptyList(),
    val rankedVideos: List<VideoItem> = emptyList(),
    val continuation: String? = null,
)

object BrowseParser {

    private const val TAG = "BrowseParser"
    private const val MAX_NODES = 8_000

    fun parse(response: JSONObject, type: DiscoveryType): BrowsePage {
        return try {
            when (type) {
                DiscoveryType.NEW_RELEASES -> parseNewReleases(response)
                DiscoveryType.CHARTS -> parseCharts(response)
                DiscoveryType.MOODS_AND_GENRES -> parseMoods(response)
            }
        } catch (e: Exception) {
            Log.e(TAG, "parse failed type=$type", e)
            BrowsePage()
        }
    }

    fun parseVideoList(response: JSONObject): BrowsePage {
        return BrowsePage(
            rankedVideos = extractVideos(response),
            continuation = extractContinuation(response),
        )
    }

    private fun parseNewReleases(response: JSONObject): BrowsePage {
        val videos = extractVideos(response)
        val featured = videos.firstOrNull()
        val shelf = videos.drop(1).take(20)
        return BrowsePage(
            featuredVideo = featured,
            sections = if (shelf.isNotEmpty()) {
                listOf(BrowseSection(title = "New & trending", videos = shelf))
            } else {
                emptyList()
            },
            continuation = extractContinuation(response),
        )
    }

    private fun parseCharts(response: JSONObject): BrowsePage {
        return BrowsePage(
            rankedVideos = extractVideos(response).take(50),
            continuation = extractContinuation(response),
        )
    }

    private fun parseMoods(response: JSONObject): BrowsePage {
        val moods = LinkedHashMap<String, BrowseMoodItem>()
        var nodesVisited = 0
        val queue = ArrayDeque<Any>()
        queue.add(response)

        while (queue.isNotEmpty() && nodesVisited < MAX_NODES) {
            when (val node = queue.removeFirst()) {
                is JSONObject -> {
                    nodesVisited++
                    node.optJSONObject("gridRenderer")?.let { grid ->
                        val items = grid.optJSONArray("items") ?: JSONArray()
                        for (index in 0 until items.length()) {
                            val item = items.optJSONObject(index) ?: continue
                            val renderer = item.optJSONObject("tileRenderer")
                                ?: item.optJSONObject("gridShelfViewModel")
                                ?: continue
                            val browseId = renderer.optJSONObject("onSelectCommand")
                                ?.optJSONObject("browseEndpoint")
                                ?.optString("browseId")
                                ?: renderer.optJSONObject("navigationEndpoint")
                                    ?.optJSONObject("browseEndpoint")
                                    ?.optString("browseId")
                                ?: continue
                            val title = extractText(renderer.optJSONObject("title"))
                                ?: extractText(renderer.optJSONObject("header"))
                                ?: continue
                            moods[browseId] = BrowseMoodItem(
                                browseId = browseId,
                                title = title,
                                thumbnailUrl = pickThumbnailUrl(renderer.optJSONObject("thumbnail")),
                                accentColorArgb = renderer.optJSONObject("style")
                                    ?.optString("backgroundColor")
                                    ?.let { parseColorHex(it) },
                            )
                        }
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

        return BrowsePage(
            moodItems = moods.values.toList(),
            continuation = extractContinuation(response),
        )
    }

    private fun extractVideos(response: JSONObject): List<VideoItem> {
        val videos = LinkedHashMap<String, VideoItem>()
        var nodesVisited = 0
        val queue = ArrayDeque<Any>()
        queue.add(response)

        while (queue.isNotEmpty() && nodesVisited < MAX_NODES) {
            when (val node = queue.removeFirst()) {
                is JSONObject -> {
                    nodesVisited++
                    extractVideo(node)?.let { video ->
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
        return videos.values.toList()
    }

    private fun extractVideo(node: JSONObject): VideoItem? {
        for (key in listOf("videoRenderer", "gridVideoRenderer", "compactVideoRenderer")) {
            if (!node.has(key)) continue
            val renderer = node.optJSONObject(key) ?: continue
            val videoId = renderer.optString("videoId").takeIf { it.isNotBlank() } ?: continue
            val title = extractText(renderer.optJSONObject("title")) ?: continue
            return VideoItem(
                videoId = videoId,
                title = title,
                channelName = extractText(renderer.optJSONObject("ownerText"))
                    ?: extractText(renderer.optJSONObject("shortBylineText"))
                    ?: "Unknown",
                channelId = null,
                thumbnailUrl = pickThumbnailUrl(renderer.optJSONObject("thumbnail"))
                    ?: "https://i.ytimg.com/img/no_thumbnail.jpg",
                durationText = extractText(renderer.optJSONObject("lengthText")),
                viewCountText = extractText(renderer.optJSONObject("shortViewCountText")),
                publishedTimeText = extractText(renderer.optJSONObject("publishedTimeText")),
            )
        }
        return null
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
        val queue = ArrayDeque<Any>()
        queue.add(response)
        var nodesVisited = 0
        while (queue.isNotEmpty() && nodesVisited < MAX_NODES) {
            when (val node = queue.removeFirst()) {
                is JSONObject -> {
                    nodesVisited++
                    val token = node.optJSONObject("continuationItemRenderer")
                        ?.optJSONObject("continuationEndpoint")
                        ?.optJSONObject("continuationCommand")
                        ?.optString("token")
                    if (!token.isNullOrBlank()) return token
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
        return null
    }

    private fun parseColorHex(raw: String): Int? {
        val hex = raw.removePrefix("#")
        return runCatching {
            when (hex.length) {
                6 -> android.graphics.Color.parseColor("#$hex")
                8 -> android.graphics.Color.parseColor("#$hex")
                else -> null
            }
        }.getOrNull()
    }
}
