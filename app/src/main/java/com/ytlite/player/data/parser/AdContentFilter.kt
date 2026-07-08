package com.ytlite.player.data.parser

import org.json.JSONObject

object AdContentFilter {

    val AD_RENDERER_KEYS = setOf(
        "adVideoRenderer",
        "promotedSparklesWebRenderer",
        "displayAdRenderer",
        "promotedVideoRenderer",
        "compactPromotedVideoRenderer",
        "compactAdRenderer",
        "adSlotRenderer",
        "inFeedAdLayoutRenderer",
        "promotedSparklesTextSearchRenderer",
    )

    fun isAdNode(node: JSONObject): Boolean {
        val type = node.optString("type")
        if (type.equals("ad", ignoreCase = true)) return true
        val render = node.optString("render")
        if (render.equals("promoted", ignoreCase = true)) return true
        if (AD_RENDERER_KEYS.any { node.has(it) }) return true
        return containsSponsoredText(node)
    }

    fun isAdRendererKey(key: String): Boolean = key in AD_RENDERER_KEYS

    private fun containsSponsoredText(node: JSONObject): Boolean {
        val keys = node.keys()
        while (keys.hasNext()) {
            val value = node.opt(keys.next())
            when (value) {
                is String -> {
                    val lower = value.lowercase()
                    if (lower.contains("sponsored") || lower == "promoted") return true
                }
                is JSONObject -> if (containsSponsoredText(value)) return true
            }
        }
        return false
    }
}
