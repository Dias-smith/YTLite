package com.ytlite.player.data.js

import org.json.JSONObject

class JsExtractorClient(
    private val engine: JsExtractorEngine,
) {
    suspend fun search(
        keyword: String,
        continuation: String? = null,
    ): JSONObject {
        val data = JSONObject().apply {
            put("keyword", keyword)
            put("filter", FILTER_ALL)
            if (continuation.isNullOrBlank()) {
                put("next", JSONObject.NULL)
            } else {
                put("next", continuation)
            }
        }
        return engine.invoke(EVENT_SEARCH, SOURCE_YTB, data)
    }

    suspend fun extract(videoUrl: String): JSONObject {
        val data = JSONObject().apply {
            put("url", videoUrl)
        }
        return engine.invoke(EVENT_EXTRACT, SOURCE_YTB, data)
    }

    suspend fun extractVideo(videoId: String): JSONObject {
        return extract("https://www.youtube.com/watch?v=$videoId")
    }

    companion object {
        const val EVENT_EXTRACT = 0
        const val EVENT_SEARCH = 1
        const val SOURCE_YTB = 0
        const val FILTER_ALL = 0
    }
}
