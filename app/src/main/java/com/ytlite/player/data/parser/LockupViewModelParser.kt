package com.ytlite.player.data.parser

import com.ytlite.player.data.model.VideoItem
import org.json.JSONArray
import org.json.JSONObject

/**
 * Parses YouTube's lockupViewModel format (2025+ API) used in browse / search feeds.
 */
object LockupViewModelParser {

    private val VIDEO_CONTENT_TYPES = setOf(
        "LOCKUP_CONTENT_TYPE_VIDEO",
        "LOCKUP_CONTENT_TYPE_VIDEO_SHORT",
    )

    private const val PLAYLIST_CONTENT_TYPE = "LOCKUP_CONTENT_TYPE_PLAYLIST"

    data class PlaylistLockup(
        val playlistId: String,
        val title: String,
        val subtitle: String,
        val thumbnailUrl: String?,
        val videoCountText: String?,
    )

    fun parseVideo(lockup: JSONObject): VideoItem? {
        val contentType = lockup.optString("contentType")
        if (contentType !in VIDEO_CONTENT_TYPES) return null

        val videoId = lockup.optString("contentId").takeIf { it.isNotBlank() } ?: return null
        val metadata = lockup.optJSONObject("metadata")?.optJSONObject("lockupMetadataViewModel")
        val title = metadata?.optJSONObject("title")?.optString("content")?.takeIf { it.isNotBlank() }
            ?: return null

        val metaParts = collectMetadataTexts(metadata)
        val channelName = metaParts.firstOrNull { isChannelNameCandidate(it) } ?: "Unknown"
        val viewCountText = metaParts.firstOrNull { isViewCountText(it) }
        val publishedTimeText = metaParts.firstOrNull { isPublishedText(it) }

        val thumbnailUrl = pickThumbnailUrl(lockup) ?: "https://i.ytimg.com/img/no_thumbnail.jpg"
        val durationText = extractDurationText(lockup)

        return VideoItem(
            videoId = videoId,
            title = title,
            channelName = channelName,
            channelId = null,
            thumbnailUrl = thumbnailUrl,
            durationText = durationText,
            viewCountText = viewCountText,
            publishedTimeText = publishedTimeText,
        )
    }

    fun parsePlaylist(lockup: JSONObject): PlaylistLockup? {
        if (lockup.optString("contentType") != PLAYLIST_CONTENT_TYPE) return null
        val playlistId = lockup.optString("contentId").takeIf { it.isNotBlank() } ?: return null
        val metadata = lockup.optJSONObject("metadata")?.optJSONObject("lockupMetadataViewModel")
        val title = metadata?.optJSONObject("title")?.optString("content")?.takeIf { it.isNotBlank() }
            ?: return null
        val metaParts = collectMetadataTexts(metadata)
        val owner = metaParts.firstOrNull { isChannelNameCandidate(it) }.orEmpty()
        val videoCountText = extractPlaylistBadgeText(lockup)
            ?: metaParts.firstOrNull { it.contains("video", ignoreCase = true) }
        return PlaylistLockup(
            playlistId = playlistId,
            title = title,
            subtitle = listOfNotNull(owner.takeIf { it.isNotBlank() }, videoCountText).joinToString(" · "),
            thumbnailUrl = pickThumbnailUrl(lockup),
            videoCountText = videoCountText,
        )
    }

    private fun collectMetadataTexts(metadata: JSONObject?): List<String> {
        if (metadata == null) return emptyList()
        val container = metadata.optJSONObject("metadata")
            ?.optJSONObject("contentMetadataViewModel")
            ?: return emptyList()
        val rows = container.optJSONArray("metadataRows") ?: return emptyList()
        val texts = mutableListOf<String>()
        for (rowIndex in 0 until rows.length()) {
            val parts = rows.optJSONObject(rowIndex)?.optJSONArray("metadataParts") ?: continue
            for (partIndex in 0 until parts.length()) {
                val text = parts.optJSONObject(partIndex)
                    ?.optJSONObject("text")
                    ?.optString("content")
                    ?.trim()
                    ?.takeIf { it.isNotBlank() }
                if (text != null) texts.add(text)
            }
        }
        return texts
    }

    private fun isChannelNameCandidate(text: String): Boolean {
        val lower = text.lowercase()
        return !isViewCountText(text) &&
            !isPublishedText(text) &&
            !lower.contains("subscriber") &&
            !lower.contains("subscribers") &&
            !lower.contains("video")
    }

    private fun isViewCountText(text: String): Boolean {
        val lower = text.lowercase()
        return lower.contains("view") || lower.contains("watching")
    }

    private fun isPublishedText(text: String): Boolean {
        val lower = text.lowercase()
        return lower.contains("ago") ||
            lower.contains("streamed") ||
            lower.contains("premiered") ||
            lower.contains("hour") ||
            lower.contains("day") ||
            lower.contains("week") ||
            lower.contains("month") ||
            lower.contains("year")
    }

    private fun pickThumbnailUrl(lockup: JSONObject): String? {
        val contentImage = lockup.optJSONObject("contentImage") ?: return null
        val sources = contentImage
            .optJSONObject("thumbnailViewModel")
            ?.optJSONObject("image")
            ?.optJSONArray("sources")
            ?: contentImage
                .optJSONObject("collectionThumbnailViewModel")
                ?.optJSONObject("primaryThumbnail")
                ?.optJSONObject("thumbnailViewModel")
                ?.optJSONObject("image")
                ?.optJSONArray("sources")
            ?: return null
        return pickLastUrl(sources)
    }

    private fun pickLastUrl(sources: JSONArray): String? {
        if (sources.length() == 0) return null
        return sources.optJSONObject(sources.length() - 1)
            ?.optString("url")
            ?.takeIf { it.isNotBlank() }
    }

    private fun extractDurationText(lockup: JSONObject): String? {
        val overlays = lockup.optJSONObject("contentImage")
            ?.optJSONObject("thumbnailViewModel")
            ?.optJSONArray("overlays")
            ?: return null
        for (overlayIndex in 0 until overlays.length()) {
            val badges = overlays.optJSONObject(overlayIndex)
                ?.optJSONObject("thumbnailBottomOverlayViewModel")
                ?.optJSONArray("badges")
                ?: continue
            for (badgeIndex in 0 until badges.length()) {
                val text = badges.optJSONObject(badgeIndex)
                    ?.optJSONObject("thumbnailBadgeViewModel")
                    ?.optString("text")
                    ?.takeIf { it.isNotBlank() }
                if (text != null) return text
            }
        }
        return null
    }

    private fun extractPlaylistBadgeText(lockup: JSONObject): String? {
        val overlays = lockup.optJSONObject("contentImage")
            ?.optJSONObject("collectionThumbnailViewModel")
            ?.optJSONObject("primaryThumbnail")
            ?.optJSONObject("thumbnailViewModel")
            ?.optJSONArray("overlays")
            ?: return null
        for (overlayIndex in 0 until overlays.length()) {
            val badges = overlays.optJSONObject(overlayIndex)
                ?.optJSONObject("thumbnailOverlayBadgeViewModel")
                ?.optJSONArray("thumbnailBadges")
                ?: continue
            for (badgeIndex in 0 until badges.length()) {
                val text = badges.optJSONObject(badgeIndex)
                    ?.optJSONObject("thumbnailBadgeViewModel")
                    ?.optString("text")
                    ?.takeIf { it.isNotBlank() }
                if (text != null) return text
            }
        }
        return null
    }
}
