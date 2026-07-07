package com.ytlite.player.data.remote.youtube

import com.ytlite.player.data.model.ChannelPage
import com.ytlite.player.data.model.SubscriptionChannel
import com.ytlite.player.data.parser.LockupViewModelParser
import org.json.JSONArray
import org.json.JSONObject
import java.util.ArrayDeque

object SubscriptionChannelParser {

    private const val MAX_NODES = 8_000

    fun parse(response: JSONObject): ChannelPage? {
        val channels = linkedMapOf<String, SubscriptionChannel>()
        var nodesVisited = 0
        val queue = ArrayDeque<Any>()
        collectParseRoots(response).forEach { queue.add(it) }

        while (queue.isNotEmpty() && nodesVisited < MAX_NODES) {
            when (val node = queue.removeFirst()) {
                is JSONObject -> {
                    nodesVisited++
                    extractChannel(node)?.let { channel ->
                        channels[channel.channelId] = channel
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

        if (channels.isEmpty()) return null
        return ChannelPage(
            channels = channels.values.toList(),
            continuation = extractContinuation(response),
        )
    }

    private fun extractChannel(node: JSONObject): SubscriptionChannel? {
        node.optJSONObject("lockupViewModel")?.let { lockup ->
            LockupViewModelParser.parseChannel(lockup)?.let { return it }
        }

        node.optJSONObject("richItemRenderer")
            ?.optJSONObject("content")
            ?.let { content -> extractChannel(content)?.let { return it } }

        val renderer = node.optJSONObject("channelRenderer")
            ?: node.optJSONObject("gridChannelRenderer")
            ?: node.optJSONObject("compactChannelRenderer")
            ?: return null

        val channelId = renderer.optString("channelId")
            .ifBlank {
                renderer.optJSONObject("navigationEndpoint")
                    ?.optJSONObject("browseEndpoint")
                    ?.optString("browseId")
                    .orEmpty()
            }
        if (channelId.isBlank()) return null

        val title = extractText(renderer.optJSONObject("title")) ?: return null
        val avatarUrl = pickThumbnailUrl(renderer.optJSONObject("thumbnail"))
            ?: return null

        val subscriberLine = extractText(renderer.optJSONObject("subscriberCountText"))
            ?: extractText(renderer.optJSONObject("videoCountText"))
        val (handle, subscriberCountText) = parseSubscriberLine(subscriberLine)

        val description = extractText(renderer.optJSONObject("descriptionSnippet"))
            ?: extractText(renderer.optJSONObject("description"))

        return SubscriptionChannel(
            channelId = channelId,
            title = title,
            handle = handle,
            avatarUrl = avatarUrl,
            subscriberCountText = subscriberCountText,
            description = description,
        )
    }

    private fun parseSubscriberLine(line: String?): Pair<String?, String?> {
        if (line.isNullOrBlank()) return null to null
        val parts = line.split("•", limit = 2).map { it.trim() }
        return when {
            parts.size == 2 && parts[0].startsWith("@") -> parts[0] to parts[1]
            line.startsWith("@") -> line to null
            else -> null to line
        }
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
                    if (node.has("continuationItemRenderer")) {
                        val token = node.optJSONObject("continuationItemRenderer")
                            ?.optJSONObject("continuationEndpoint")
                            ?.optJSONObject("continuationCommand")
                            ?.optString("token")
                        if (!token.isNullOrBlank()) return token
                    }
                    if (node.has("continuationItemViewModel")) {
                        val token = node.optJSONObject("continuationItemViewModel")
                            ?.optJSONObject("continuationCommand")
                            ?.optJSONObject("innertubeCommand")
                            ?.optJSONObject("continuationCommand")
                            ?.optString("token")
                        if (!token.isNullOrBlank()) return token
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
        return null
    }

    private fun collectParseRoots(response: JSONObject): List<Any> {
        val roots = mutableListOf<Any>(response)
        for (actionsKey in listOf("onResponseReceivedActions", "onResponseReceivedCommands")) {
            val actions = response.optJSONArray(actionsKey) ?: continue
            for (index in 0 until actions.length()) {
                val action = actions.optJSONObject(index) ?: continue
                for (commandKey in listOf("appendContinuationItemsAction", "reloadContinuationItemsCommand")) {
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
}
