package com.ytlite.player.data.parser

import android.util.Log
import com.ytlite.player.data.model.VideoItem
import org.json.JSONArray
import org.json.JSONObject
import java.util.ArrayDeque

data class MusicAlbumRelease(
    val browseId: String,
    val title: String,
    val artistName: String,
    val thumbnailUrl: String,
    val releaseType: String,
    val playlistId: String?,
) {
    val isSingle: Boolean
        get() = releaseType.equals("Single", ignoreCase = true) ||
            releaseType == "单曲" ||
            releaseType == "シングル"
}

/**
 * Parses YouTube Music [FEmusic_new_releases](https://music.youtube.com/new_releases/albums)
 * album cards and album-detail song lists.
 */
object MusicNewReleasesParser {

    private const val TAG = "MusicNewReleasesParser"
    private const val MAX_NODES = 10_000

    fun parseAlbumReleases(response: JSONObject): List<MusicAlbumRelease> {
        val albums = LinkedHashMap<String, MusicAlbumRelease>()
        walk(response) { node ->
            val renderer = node.optJSONObject("musicTwoRowItemRenderer") ?: return@walk
            val browseId = renderer
                .optJSONObject("navigationEndpoint")
                ?.optJSONObject("browseEndpoint")
                ?.optString("browseId")
                ?.takeIf { it.startsWith("MPRE") }
                ?: return@walk
            val title = extractText(renderer.optJSONObject("title")) ?: return@walk
            val subtitle = renderer.optJSONObject("subtitle")
            albums.putIfAbsent(
                browseId,
                MusicAlbumRelease(
                    browseId = browseId,
                    title = title,
                    artistName = extractAlbumArtist(subtitle),
                    thumbnailUrl = pickThumbnailUrl(renderer)
                        ?: "https://i.ytimg.com/img/no_thumbnail.jpg",
                    releaseType = extractReleaseType(subtitle),
                    playlistId = extractPlaylistId(renderer),
                ),
            )
        }
        Log.d(TAG, "parseAlbumReleases count=${albums.size}")
        return albums.values.toList()
    }

    fun parseAlbumTracks(
        response: JSONObject,
        albumTitle: String,
        artistFallback: String,
        thumbnailFallback: String,
    ): List<VideoItem> {
        val tracks = LinkedHashMap<String, VideoItem>()
        walk(response) { node ->
            val renderer = node.optJSONObject("musicResponsiveListItemRenderer") ?: return@walk
            val videoId = renderer.optJSONObject("playlistItemData")
                ?.optString("videoId")
                ?.takeIf { it.isNotBlank() }
                ?: renderer.optJSONObject("overlay")
                    ?.optJSONObject("musicItemThumbnailOverlayRenderer")
                    ?.optJSONObject("content")
                    ?.optJSONObject("musicPlayButtonRenderer")
                    ?.optJSONObject("playNavigationEndpoint")
                    ?.optJSONObject("watchEndpoint")
                    ?.optString("videoId")
                    ?.takeIf { it.isNotBlank() }
                ?: return@walk
            val columns = renderer.optJSONArray("flexColumns")
            val title = columns
                ?.optJSONObject(0)
                ?.optJSONObject("musicResponsiveListItemFlexColumnRenderer")
                ?.optJSONObject("text")
                ?.let { extractText(it) }
                ?: return@walk
            val artist = columns
                ?.optJSONObject(1)
                ?.optJSONObject("musicResponsiveListItemFlexColumnRenderer")
                ?.optJSONObject("text")
                ?.let { extractText(it) }
                ?.takeIf { it.isNotBlank() }
                ?: artistFallback
            tracks.putIfAbsent(
                videoId,
                VideoItem(
                    videoId = videoId,
                    title = title,
                    channelName = artist.ifBlank { albumTitle },
                    channelId = null,
                    thumbnailUrl = pickThumbnailUrl(renderer) ?: thumbnailFallback,
                    durationText = columns
                        ?.optJSONObject(columns.length() - 1)
                        ?.optJSONObject("musicResponsiveListItemFlexColumnRenderer")
                        ?.optJSONObject("text")
                        ?.let { extractText(it) }
                        ?.takeIf { it.contains(':') },
                    viewCountText = null,
                    publishedTimeText = albumTitle.takeIf { it.isNotBlank() },
                ),
            )
        }
        return tracks.values.toList()
    }

    fun extractContinuation(response: JSONObject): String? {
        var found: String? = null
        walk(response) { node ->
            if (found != null) return@walk
            val token = node.optJSONObject("continuationEndpoint")
                ?.optJSONObject("continuationCommand")
                ?.optString("token")
                ?.takeIf { it.isNotBlank() }
                ?: node.optJSONObject("nextContinuationData")
                    ?.optString("continuation")
                    ?.takeIf { it.isNotBlank() }
            if (token != null) found = token
        }
        return found
    }

    private inline fun walk(root: JSONObject, onObject: (JSONObject) -> Unit) {
        val queue = ArrayDeque<Any>()
        queue.add(root)
        var visited = 0
        while (queue.isNotEmpty() && visited < MAX_NODES) {
            when (val node = queue.removeFirst()) {
                is JSONObject -> {
                    visited++
                    onObject(node)
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
    }

    private fun pickThumbnailUrl(renderer: JSONObject): String? {
        val candidates = listOf(
            renderer.optJSONObject("thumbnailRenderer")
                ?.optJSONObject("musicThumbnailRenderer")
                ?.optJSONObject("thumbnail"),
            renderer.optJSONObject("thumbnail")
                ?.optJSONObject("musicThumbnailRenderer")
                ?.optJSONObject("thumbnail"),
            renderer.optJSONObject("thumbnail"),
        )
        for (thumbnail in candidates) {
            val thumbs = thumbnail?.optJSONArray("thumbnails") ?: continue
            if (thumbs.length() == 0) continue
            val url = thumbs.optJSONObject(thumbs.length() - 1)
                ?.optString("url")
                ?.takeIf { it.isNotBlank() }
            if (url != null) return url
        }
        return null
    }

    private fun extractReleaseType(subtitle: JSONObject?): String {
        val runs = subtitle?.optJSONArray("runs") ?: return ""
        val first = runs.optJSONObject(0)?.optString("text")?.trim().orEmpty()
        return first.takeIf { it.isNotBlank() && it != "•" }.orEmpty()
    }

    private fun extractPlaylistId(renderer: JSONObject): String? {
        val fromOverlay = renderer.optJSONObject("thumbnailOverlay")
            ?.optJSONObject("musicItemThumbnailOverlayRenderer")
            ?.optJSONObject("content")
            ?.optJSONObject("musicPlayButtonRenderer")
            ?.optJSONObject("playNavigationEndpoint")
            ?.optJSONObject("watchPlaylistEndpoint")
            ?.optString("playlistId")
            ?.takeIf { it.isNotBlank() }
        if (fromOverlay != null) return fromOverlay

        val menuItems = renderer.optJSONObject("menu")
            ?.optJSONObject("menuRenderer")
            ?.optJSONArray("items")
            ?: return null
        for (index in 0 until menuItems.length()) {
            val playlistId = menuItems.optJSONObject(index)
                ?.optJSONObject("menuNavigationItemRenderer")
                ?.optJSONObject("navigationEndpoint")
                ?.optJSONObject("watchPlaylistEndpoint")
                ?.optString("playlistId")
                ?.takeIf { it.isNotBlank() }
            if (playlistId != null) return playlistId
        }
        return null
    }

    private fun extractAlbumArtist(subtitle: JSONObject?): String {
        val runs = subtitle?.optJSONArray("runs") ?: return extractText(subtitle).orEmpty()
        val artists = mutableListOf<String>()
        for (index in 0 until runs.length()) {
            val run = runs.optJSONObject(index) ?: continue
            val text = run.optString("text").trim()
            if (text.isBlank() || text == "•" || text == "Album" || text == "EP" || text == "Single") {
                continue
            }
            artists += text.trim(' ', '•')
        }
        return artists.joinToString(", ").ifBlank { extractText(subtitle).orEmpty() }
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
}
