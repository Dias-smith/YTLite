package com.ytlite.player.data.parser

import com.ytlite.player.data.model.VideoItem
import org.json.JSONArray
import org.json.JSONObject

/**
 * Parses YouTube's lockupViewModel format (2025+ API) used in browse feeds.
 */
object LockupViewModelParser {

    private val VIDEO_CONTENT_TYPES = setOf(
        "LOCKUP_CONTENT_TYPE_VIDEO",
        "LOCKUP_CONTENT_TYPE_VIDEO_SHORT",
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
            !lower.contains("subscribers")
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
        val sources = lockup.optJSONObject("contentImage")
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
}
