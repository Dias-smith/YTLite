package com.ytlite.player.data.parser

import android.util.Log
import com.ytlite.player.data.model.SearchResultItem
import com.ytlite.player.data.model.SearchResultPage
import com.ytlite.player.data.model.SearchResultTab
import com.ytlite.player.data.model.SearchSuggestion
import org.json.JSONArray
import org.json.JSONObject
import java.util.ArrayDeque

object SearchResultParser {

    private const val TAG = "SearchResultParser"
    private const val MAX_NODES = 8_000

    private val VIDEO_KEYS = setOf("videoRenderer", "gridVideoRenderer", "compactVideoRenderer")
    private val CHANNEL_KEYS = setOf("channelRenderer", "gridChannelRenderer")
    private val PLAYLIST_KEYS = setOf("playlistRenderer", "gridPlaylistRenderer")

    fun parseResults(response: JSONObject, tab: SearchResultTab): SearchResultPage {
        val items = LinkedHashMap<String, SearchResultItem>()
        var nodesVisited = 0
        val queue = ArrayDeque<Any>()
        queue.add(response)

        while (queue.isNotEmpty() && nodesVisited < MAX_NODES) {
            when (val node = queue.removeFirst()) {
                is JSONObject -> {
                    nodesVisited++
                    extractItem(node, tab)?.let { item ->
                        items.putIfAbsent(item.id, item)
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
        Log.d(TAG, "parseResults tab=$tab items=${items.size} continuation=${continuation != null}")
        return SearchResultPage(items.values.toList(), continuation)
    }

    fun parseSuggestions(response: JSONObject, query: String, historyQueries: List<String>): List<SearchSuggestion> {
        val suggestions = LinkedHashMap<String, SearchSuggestion>()
        val lowerQuery = query.lowercase()

        historyQueries
            .filter { it.contains(query, ignoreCase = true) && it.lowercase() != lowerQuery }
            .take(3)
            .forEach { history ->
                suggestions["query:$history"] = SearchSuggestion.Query(
                    id = "query:$history",
                    text = history,
                    isFromHistory = true,
                )
            }

        val page = parseResults(response, SearchResultTab.ALL)
        page.items.forEach { item ->
            when (item) {
                is SearchResultItem.Video -> {
                    if (suggestions.size >= 12) return@forEach
                    suggestions[item.videoId] = SearchSuggestion.Video(
                        id = item.videoId,
                        videoId = item.videoId,
                        title = item.title,
                        subtitle = item.subtitle,
                        thumbnailUrl = item.thumbnailUrl,
                    )
                }
                is SearchResultItem.Channel -> {
                    if (suggestions.size >= 12) return@forEach
                    suggestions[item.channelId] = SearchSuggestion.Channel(
                        id = item.channelId,
                        channelId = item.channelId,
                        title = item.title,
                        subtitle = item.subtitle,
                        avatarUrl = item.thumbnailUrl,
                    )
                }
                is SearchResultItem.Playlist -> Unit
            }
        }

        if (!suggestions.containsKey("query:$query")) {
            suggestions["query:$query"] = SearchSuggestion.Query(
                id = "query:$query",
                text = query,
                isFromHistory = historyQueries.any { it.equals(query, ignoreCase = true) },
            )
        }

        return suggestions.values.toList()
    }

    private fun extractItem(node: JSONObject, tab: SearchResultTab): SearchResultItem? {
        for (key in VIDEO_KEYS) {
            if (!node.has(key)) continue
            if (tab == SearchResultTab.CHANNELS || tab == SearchResultTab.PLAYLISTS) continue
            node.optJSONObject(key)?.let { return mapVideo(it) }
        }
        for (key in CHANNEL_KEYS) {
            if (!node.has(key)) continue
            if (tab == SearchResultTab.VIDEOS || tab == SearchResultTab.PLAYLISTS) continue
            node.optJSONObject(key)?.let { return mapChannel(it) }
        }
        for (key in PLAYLIST_KEYS) {
            if (!node.has(key)) continue
            if (tab == SearchResultTab.VIDEOS || tab == SearchResultTab.CHANNELS) continue
            node.optJSONObject(key)?.let { return mapPlaylist(it) }
        }
        return null
    }

    private fun mapVideo(renderer: JSONObject): SearchResultItem.Video? {
        val videoId = renderer.optString("videoId").takeIf { it.isNotBlank() } ?: return null
        val title = extractText(renderer.optJSONObject("title")) ?: return null
        val channelName = extractText(renderer.optJSONObject("ownerText"))
            ?: extractText(renderer.optJSONObject("shortBylineText"))
            ?: ""
        val viewCount = extractText(renderer.optJSONObject("shortViewCountText"))
            ?: extractText(renderer.optJSONObject("viewCountText"))
        val channelId = extractChannelId(renderer)
        return SearchResultItem.Video(
            id = videoId,
            videoId = videoId,
            title = title,
            subtitle = listOfNotNull(channelName, viewCount).joinToString(" · ").ifBlank { channelName },
            thumbnailUrl = pickThumbnailUrl(renderer.optJSONObject("thumbnail")),
            channelName = channelName,
            channelId = channelId,
            viewCountText = viewCount,
        )
    }

    private fun mapChannel(renderer: JSONObject): SearchResultItem.Channel? {
        val channelId = renderer.optString("channelId")
            .takeIf { it.isNotBlank() }
            ?: renderer.optString("browseId").takeIf { it.isNotBlank() }
            ?: return null
        val title = extractText(renderer.optJSONObject("title")) ?: return null
        val subtitle = extractText(renderer.optJSONObject("subscriberCountText"))
            ?: extractText(renderer.optJSONObject("videoCountText"))
            ?: ""
        return SearchResultItem.Channel(
            id = channelId,
            channelId = channelId,
            title = title,
            subtitle = subtitle,
            thumbnailUrl = pickChannelAvatarUrl(renderer),
        )
    }

    private fun mapPlaylist(renderer: JSONObject): SearchResultItem.Playlist? {
        val playlistId = renderer.optString("playlistId").takeIf { it.isNotBlank() } ?: return null
        val title = extractText(renderer.optJSONObject("title")) ?: return null
        val subtitle = extractText(renderer.optJSONObject("shortBylineText"))
            ?: extractText(renderer.optJSONObject("longBylineText"))
            ?: ""
        val videoCount = extractText(renderer.optJSONObject("videoCountText"))
        return SearchResultItem.Playlist(
            id = playlistId,
            playlistId = playlistId,
            title = title,
            subtitle = subtitle,
            thumbnailUrl = pickThumbnailUrl(renderer.optJSONObject("thumbnail")),
            videoCountText = videoCount,
        )
    }

    private fun extractChannelId(renderer: JSONObject): String? {
        renderer.optString("channelId").takeIf { it.isNotBlank() }?.let { return it }
        val runs = renderer.optJSONObject("ownerText")?.optJSONArray("runs")
            ?: renderer.optJSONObject("shortBylineText")?.optJSONArray("runs")
            ?: renderer.optJSONObject("longBylineText")?.optJSONArray("runs")
        if (runs != null) {
            for (index in 0 until runs.length()) {
                val browseId = runs.optJSONObject(index)?.optJSONObject("navigationEndpoint")
                    ?.optJSONObject("browseEndpoint")?.optString("browseId")?.takeIf { it.isNotBlank() }
                if (browseId != null) return browseId
            }
        }
        return null
    }

    /**
     * Channel avatars live under [channelThumbnailSupportedRenderers] for current InnerTube
     * search responses; older payloads still use top-level [thumbnail].
     */
    private fun pickChannelAvatarUrl(renderer: JSONObject): String? {
        val supported = renderer.optJSONObject("channelThumbnailSupportedRenderers")
            ?.optJSONObject("channelThumbnailWithLinkRenderer")
            ?.optJSONObject("thumbnail")
        return pickThumbnailUrl(supported)
            ?: pickThumbnailUrl(renderer.optJSONObject("thumbnail"))
            ?: pickThumbnailUrl(renderer.optJSONObject("avatar"))
    }

    private fun pickThumbnailUrl(thumbnail: JSONObject?): String? {
        val thumbnails = thumbnail?.optJSONArray("thumbnails") ?: return null
        if (thumbnails.length() == 0) return null
        val raw = thumbnails.optJSONObject(thumbnails.length() - 1)
            ?.optString("url")
            ?.takeIf { it.isNotBlank() }
            ?: return null
        return normalizeThumbnailUrl(raw)
    }

    private fun normalizeThumbnailUrl(url: String): String =
        when {
            url.startsWith("//") -> "https:$url"
            url.startsWith("http://") -> "https://${url.removePrefix("http://")}"
            else -> url
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
                        ?: node.optJSONObject("continuationItemViewModel")
                            ?.optJSONObject("continuationCommand")
                            ?.optJSONObject("innertubeCommand")
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
}
