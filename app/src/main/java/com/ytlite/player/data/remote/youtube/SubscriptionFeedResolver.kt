package com.ytlite.player.data.remote.youtube

import com.ytlite.player.data.network.InnerTubeApi
import com.ytlite.player.data.network.InnerTubeConfig
import com.ytlite.player.data.parser.FeedParser
import com.ytlite.player.data.youtube.YoutubeDiagnostics
import org.json.JSONArray
import org.json.JSONObject
import java.util.ArrayDeque

/**
 * Resolves the subscriptions feed shell into a payload that contains video items.
 *
 * The initial [FEsubscriptions] response is often a filter shell (chips + channel strip)
 * without video renderers. Following chip browseEndpoints loads the real feed.
 */
object SubscriptionFeedResolver {

    private val ALL_FILTER_LABELS = setOf(
        "all",
        "全部",
    )

    fun resolve(initialResponse: JSONObject, innerTubeApi: InnerTubeApi): JSONObject {
        val initialPage = FeedParser.parse(initialResponse)
        if (initialPage != null && initialPage.videos.isNotEmpty()) {
            return initialResponse
        }

        val chips = findFilterChips(initialResponse)
        if (chips.isEmpty()) {
            YoutubeDiagnostics.w(
                "SubscriptionResolver",
                "no filter chip found; rendererHistogram=${FeedParser.debugRendererHistogram(initialResponse)}",
            )
            return initialResponse
        }

        val orderedChips = orderChips(chips)
        var lastResponse = initialResponse

        for (chip in orderedChips) {
            YoutubeDiagnostics.d(
                "SubscriptionResolver",
                "following chip filter text=${chip.label} browseId=${chip.browseId} " +
                    "params=${chip.params != null} selected=${chip.isSelected}",
            )

            val filteredResponse = innerTubeApi.browseAuthenticated(
                browseId = chip.browseId,
                params = chip.params,
                label = "browse_subscriptions_chip",
            )
            lastResponse = filteredResponse

            val filteredPage = FeedParser.parse(filteredResponse)
            if (filteredPage != null && filteredPage.videos.isNotEmpty()) {
                return filteredResponse
            }
        }

        YoutubeDiagnostics.w(
            "SubscriptionResolver",
            "all ${orderedChips.size} chips empty; rendererHistogram=" +
                FeedParser.debugRendererHistogram(lastResponse),
        )
        return lastResponse
    }

    private fun orderChips(chips: List<FilterChip>): List<FilterChip> {
        val allChips = chips.filter { ALL_FILTER_LABELS.contains(it.label.lowercase()) }
        val withParams = chips.filter { !it.params.isNullOrBlank() }
        val selected = chips.filter { it.isSelected }
        return (allChips + selected + withParams + chips)
            .distinctBy { "${it.browseId}|${it.params.orEmpty()}|${it.label}" }
    }

    private fun findFilterChips(response: JSONObject): List<FilterChip> {
        val chips = mutableListOf<FilterChip>()
        collectChips(response, chips)
        return chips.filter { !it.params.isNullOrBlank() || it.isSelected }
            .ifEmpty { chips }
    }

    private fun collectChips(node: Any, out: MutableList<FilterChip>) {
        val queue = ArrayDeque<Any>()
        queue.add(node)
        var visited = 0

        while (queue.isNotEmpty() && visited < 4_000) {
            when (val current = queue.removeFirst()) {
                is JSONObject -> {
                    visited++
                    extractLegacyChip(current)?.let { out.add(it) }
                    extractViewModelChip(current)?.let { out.add(it) }
                    val keys = current.keys()
                    while (keys.hasNext()) {
                        when (val value = current.opt(keys.next())) {
                            is JSONObject, is JSONArray -> queue.add(value)
                        }
                    }
                }
                is JSONArray -> {
                    for (index in 0 until current.length()) {
                        when (val value = current.opt(index)) {
                            is JSONObject, is JSONArray -> queue.add(value)
                        }
                    }
                }
            }
        }
    }

    private fun extractLegacyChip(node: JSONObject): FilterChip? {
        val chip = node.optJSONObject("chipCloudChipRenderer") ?: return null
        val browseEndpoint = chip.optJSONObject("navigationEndpoint")?.optJSONObject("browseEndpoint")
            ?: return null
        val browseId = browseEndpoint.optString("browseId").ifBlank { InnerTubeConfig.BROWSE_ID_SUBSCRIPTIONS }
        val params = browseEndpoint.optString("params").takeIf { it.isNotBlank() }
        val label = extractChipText(chip) ?: "unknown"
        val isSelected = chip.optBoolean("isSelected", false)
        return FilterChip(label, browseId, params, isSelected)
    }

    private fun extractViewModelChip(node: JSONObject): FilterChip? {
        val chip = node.optJSONObject("chipViewModel") ?: return null
        val browseEndpoint = chip.optJSONObject("onTap")
            ?.optJSONObject("innertubeCommand")
            ?.optJSONObject("browseEndpoint")
            ?: chip.optJSONObject("navigationEndpoint")
                ?.optJSONObject("browseEndpoint")
            ?: return null
        val browseId = browseEndpoint.optString("browseId").ifBlank { InnerTubeConfig.BROWSE_ID_SUBSCRIPTIONS }
        val params = browseEndpoint.optString("params").takeIf { it.isNotBlank() }
        val label = chip.optJSONObject("text")?.optString("content")
            ?: extractChipText(chip)
            ?: "unknown"
        val isSelected = chip.optBoolean("isSelected", false)
        return FilterChip(label, browseId, params, isSelected)
    }

    private fun extractChipText(chip: JSONObject): String? {
        val simple = chip.optJSONObject("text")?.optString("simpleText")
        if (!simple.isNullOrBlank()) return simple
        val runs = chip.optJSONObject("text")?.optJSONArray("runs") ?: return null
        val builder = StringBuilder()
        for (index in 0 until runs.length()) {
            builder.append(runs.optJSONObject(index)?.optString("text").orEmpty())
        }
        return builder.toString().takeIf { it.isNotBlank() }
    }

    private data class FilterChip(
        val label: String,
        val browseId: String,
        val params: String?,
        val isSelected: Boolean,
    )
}
