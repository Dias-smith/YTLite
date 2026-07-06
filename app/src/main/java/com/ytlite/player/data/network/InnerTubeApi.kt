package com.ytlite.player.data.network

import android.util.Log
import org.json.JSONObject

class InnerTubeApi(
    private val httpClient: YouTubeHttpClient = YouTubeHttpClient.getInstance(),
) {

    fun browseHome(): JSONObject {
        val body = JSONObject().apply {
            put("context", buildClientContext(InnerTubeConfig.FEED_CLIENT))
            put("browseId", InnerTubeConfig.BROWSE_ID_HOME)
        }
        return post(
            url = InnerTubeConfig.BROWSE_URL,
            body = body,
            label = "browse",
            client = InnerTubeConfig.FEED_CLIENT,
        )
    }

    fun searchVideos(
        query: String,
        continuation: String? = null,
    ): JSONObject {
        val body = if (!continuation.isNullOrBlank()) {
            JSONObject().apply {
                put("context", buildClientContext(InnerTubeConfig.FEED_CLIENT))
                put("continuation", continuation)
            }
        } else {
            JSONObject().apply {
                put("context", buildClientContext(InnerTubeConfig.FEED_CLIENT))
                put("query", query)
            }
        }
        return post(
            url = InnerTubeConfig.SEARCH_URL,
            body = body,
            label = "search",
            client = InnerTubeConfig.FEED_CLIENT,
        )
    }

    private fun post(
        url: String,
        body: JSONObject,
        label: String,
        client: InnerTubeClientType,
    ): JSONObject {
        val headers = mapOf(
            "Content-Type" to "application/json",
            "User-Agent" to InnerTubeConfig.USER_AGENT,
            "X-YouTube-Client-Name" to client.clientNameHeader,
            "X-YouTube-Client-Version" to client.clientVersion,
        )
        val result = httpClient.request(
            url = url,
            method = "POST",
            headers = headers,
            body = body.toString(),
        )
        if (!result.success || result.result.isNullOrBlank()) {
            Log.w(TAG, "$label failed code=${result.errCode} msg=${result.errMsg}")
            throw YouTubeNetworkException(
                result.errMsg.ifBlank { "InnerTube $label request failed" },
            )
        }
        return JSONObject(result.result)
    }

    private fun buildClientContext(client: InnerTubeClientType): JSONObject {
        return JSONObject().apply {
            put(
                "client",
                JSONObject().apply {
                    put("clientName", client.clientName)
                    put("clientVersion", client.clientVersion)
                    put("hl", InnerTubeConfig.HL)
                    put("gl", InnerTubeConfig.GL)
                },
            )
        }
    }

    companion object {
        private const val TAG = "InnerTubeApi"

        @Volatile
        private var instance: InnerTubeApi? = null

        fun getInstance(): InnerTubeApi =
            instance ?: synchronized(this) {
                instance ?: InnerTubeApi().also { instance = it }
            }
    }
}
