package com.ytlite.player.data.remote.youtube

import com.ytlite.player.data.local.entity.PlaylistEntity
import com.ytlite.player.data.local.entity.PlaylistTrackEntity
import com.ytlite.player.data.model.DataSource
import com.ytlite.player.data.model.PlaylistIds
import org.json.JSONArray
import org.json.JSONObject

object YoutubePlaylistParser {

    fun parsePlaylists(response: JSONObject, ownerKey: String): List<PlaylistEntity> {
        val results = linkedMapOf<String, PlaylistEntity>()
        collectPlaylistRenderers(response, ownerKey, results)
        return results.values.sortedByDescending { it.updatedAt }
    }

    fun parsePlaylistItems(response: JSONObject, playlistId: String): List<PlaylistTrackEntity> {
        val tracks = mutableListOf<PlaylistTrackEntity>()
        var position = 0
        walk(response) { obj ->
            val renderer = obj.optJSONObject("playlistVideoRenderer")
                ?: obj.optJSONObject("gridVideoRenderer")
                ?: return@walk
            val videoId = renderer.optString("videoId")
            if (videoId.isBlank()) return@walk
            tracks += PlaylistTrackEntity(
                playlistId = playlistId,
                trackId = videoId,
                position = position++,
            )
        }
        return tracks
    }

    private fun collectPlaylistRenderers(
        node: Any?,
        ownerKey: String,
        output: MutableMap<String, PlaylistEntity>,
    ) {
        when (node) {
            is JSONObject -> {
                val renderer = node.optJSONObject("playlistRenderer")
                    ?: node.optJSONObject("gridPlaylistRenderer")
                if (renderer != null) {
                    toPlaylistEntity(renderer, ownerKey)?.let { entity ->
                        output[entity.playlistId] = entity
                    }
                }
                node.keys().forEach { key ->
                    collectPlaylistRenderers(node.opt(key), ownerKey, output)
                }
            }
            is JSONArray -> {
                for (index in 0 until node.length()) {
                    collectPlaylistRenderers(node.opt(index), ownerKey, output)
                }
            }
        }
    }

    private fun toPlaylistEntity(renderer: JSONObject, ownerKey: String): PlaylistEntity? {
        val playlistId = renderer.optString("playlistId")
            .ifBlank { renderer.optString("browseId").removePrefix("VL") }
        if (playlistId.isBlank()) return null

        val title = renderer.optJSONObject("title")
            ?.optJSONArray("runs")
            ?.optJSONObject(0)
            ?.optString("text")
            ?: renderer.optString("title")
        if (title.isBlank()) return null

        val thumbnails = renderer.optJSONObject("thumbnail")
            ?: renderer.optJSONObject("thumbnails")
        val coverUrl = extractThumbnailUrl(thumbnails)

        return PlaylistEntity(
            playlistId = PlaylistIds.youtube(playlistId),
            ownerKey = ownerKey,
            name = title,
            coverUrlOrPath = coverUrl,
            description = null,
            systemType = null,
            source = DataSource.YOUTUBE.dbValue,
            isSynced = false,
            updatedAt = System.currentTimeMillis(),
        )
    }

    private fun extractThumbnailUrl(thumbnailRoot: JSONObject?): String? {
        if (thumbnailRoot == null) return null
        val thumbnails = thumbnailRoot.optJSONArray("thumbnails") ?: return null
        for (index in thumbnails.length() - 1 downTo 0) {
            val url = thumbnails.optJSONObject(index)?.optString("url")
            if (!url.isNullOrBlank()) return url
        }
        return null
    }

    private fun walk(node: Any?, block: (JSONObject) -> Unit) {
        when (node) {
            is JSONObject -> {
                block(node)
                node.keys().forEach { key -> walk(node.opt(key), block) }
            }
            is JSONArray -> {
                for (index in 0 until node.length()) {
                    walk(node.opt(index), block)
                }
            }
        }
    }
}
