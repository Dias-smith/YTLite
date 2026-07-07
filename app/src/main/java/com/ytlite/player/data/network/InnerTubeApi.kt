package com.ytlite.player.data.network

import android.util.Log
import com.ytlite.player.data.youtube.YoutubeDiagnostics
import org.json.JSONObject

class InnerTubeApi(
    private val httpClient: YouTubeHttpClient = YouTubeHttpClient.getInstance(),
) {

    fun browseHome(): JSONObject {
        return browse(InnerTubeConfig.BROWSE_ID_HOME, label = "browse_home")
    }

    fun browseLibraryPlaylists(): JSONObject {
        return browse(
            browseId = InnerTubeConfig.BROWSE_ID_LIBRARY,
            label = "browse_library",
            authenticated = true,
        )
    }

    fun browseSubscriptions(continuation: String? = null): JSONObject {
        return browse(
            browseId = InnerTubeConfig.BROWSE_ID_SUBSCRIPTIONS,
            label = "browse_subscriptions",
            continuation = continuation,
            authenticated = true,
        )
    }

    fun browseAuthenticated(
        browseId: String,
        params: String?,
        label: String,
    ): JSONObject {
        val response = postBrowseBody(
            body = buildBrowseBody(browseId, params),
            label = label,
            authenticated = true,
        )
        return resolveBrowseResponse(response, label, authenticated = true, depth = 0)
    }

    fun browseSubscriptionChannels(continuation: String? = null): JSONObject {
        return browse(
            browseId = InnerTubeConfig.BROWSE_ID_SUBSCRIPTION_CHANNELS,
            label = "browse_subscription_channels",
            continuation = continuation,
            authenticated = true,
        )
    }

    fun browseChannelVideos(channelId: String): JSONObject {
        return browseAuthenticated(
            browseId = channelId,
            params = InnerTubeConfig.BROWSE_PARAMS_CHANNEL_VIDEOS,
            label = "browse_channel_videos",
        )
    }

    fun browsePlaylistItems(youtubePlaylistId: String): JSONObject {
        val browseId = if (youtubePlaylistId.startsWith("VL")) {
            youtubePlaylistId
        } else {
            "VL$youtubePlaylistId"
        }
        return browse(browseId, label = "browse_playlist")
    }

    private fun browse(
        browseId: String,
        label: String,
        continuation: String? = null,
        authenticated: Boolean = false,
    ): JSONObject {
        val response = if (!continuation.isNullOrBlank()) {
            postBrowseBody(
                body = JSONObject().apply {
                    put("context", buildClientContext(InnerTubeConfig.FEED_CLIENT))
                    put("continuation", continuation)
                },
                label = label,
                authenticated = authenticated,
            )
        } else {
            postBrowseBody(
                body = buildBrowseBody(browseId),
                label = label,
                authenticated = authenticated,
            )
        }
        return if (authenticated) {
            resolveBrowseResponse(response, label, authenticated, depth = 0)
        } else {
            response
        }
    }

    private fun buildBrowseBody(browseId: String, params: String? = null): JSONObject =
        JSONObject().apply {
            put("context", buildClientContext(InnerTubeConfig.FEED_CLIENT))
            put("browseId", browseId)
            if (!params.isNullOrBlank()) {
                put("params", params)
            }
        }

    /**
     * Authenticated browse responses often return a shell with [onResponseReceivedActions]
     * containing navigateAction — follow it to reach the real feed payload.
     */
    private fun resolveBrowseResponse(
        response: JSONObject,
        label: String,
        authenticated: Boolean,
        depth: Int,
    ): JSONObject {
        if (depth >= MAX_NAVIGATE_DEPTH) return response

        val actions = response.optJSONArray("onResponseReceivedActions")
        if (actions != null) {
            val actionKeys = buildList {
                for (index in 0 until actions.length()) {
                    val action = actions.optJSONObject(index) ?: continue
                    val keys = action.keys()
                    while (keys.hasNext()) {
                        add(keys.next())
                    }
                }
            }
            if (actionKeys.isNotEmpty()) {
                YoutubeDiagnostics.d(TAG, "$label onResponseReceivedActions keys=$actionKeys")
            }
        }

        for (index in 0 until (actions?.length() ?: 0)) {
            val navigate = actions?.optJSONObject(index)?.optJSONObject("navigateAction") ?: continue
            val browseEndpoint = navigate
                .optJSONObject("endpoint")
                ?.optJSONObject("browseEndpoint")
                ?: continue

            val targetBrowseId = browseEndpoint.optString("browseId")
            if (targetBrowseId.isBlank()) continue

            val params = browseEndpoint.optString("params").takeIf { it.isNotBlank() }
            YoutubeDiagnostics.d(TAG, "$label navigateAction -> browseId=$targetBrowseId params=${params != null}")
            val followUp = postBrowseBody(
                body = buildBrowseBody(targetBrowseId, params),
                label = "${label}_navigate",
                authenticated = authenticated,
            )
            return resolveBrowseResponse(followUp, "${label}_navigate", authenticated, depth + 1)
        }

        return response
    }

    private fun postBrowseBody(
        body: JSONObject,
        label: String,
        authenticated: Boolean,
    ): JSONObject = post(
        url = InnerTubeConfig.BROWSE_URL,
        body = body,
        label = label,
        client = InnerTubeConfig.FEED_CLIENT,
        authenticated = authenticated,
    )

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
        authenticated: Boolean = false,
    ): JSONObject {
        val headers = mutableMapOf(
            "Content-Type" to "application/json",
            "User-Agent" to InnerTubeConfig.USER_AGENT,
            "X-YouTube-Client-Name" to client.clientNameHeader,
            "X-YouTube-Client-Version" to client.clientVersion,
        )
        if (authenticated && YoutubeCookieJar.hasAuthCookies()) {
            val authHeaders = YoutubeAuthHeaders.buildAuthenticatedHeaders()
            YoutubeDiagnostics.d(
                TAG,
                "$label authHeaders present=${authHeaders.keys} " +
                    "hasAuthorization=${authHeaders.containsKey("Authorization")}",
            )
            headers.putAll(authHeaders)
        } else if (authenticated) {
            YoutubeDiagnostics.w(
                TAG,
                "$label authenticated=true but ytSessionCookies=false " +
                    "jar=${YoutubeCookieJar.debugJarCookieNames()}",
            )
        }
        val result = httpClient.request(
            url = url,
            method = "POST",
            headers = headers,
            body = body.toString(),
        )
        if (!result.success || result.result.isNullOrBlank()) {
            Log.w(TAG, "$label failed code=${result.errCode} msg=${result.errMsg}")
            YoutubeDiagnostics.e(TAG, "$label http failed code=${result.errCode} msg=${result.errMsg}")
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
        private const val MAX_NAVIGATE_DEPTH = 3

        @Volatile
        private var instance: InnerTubeApi? = null

        fun getInstance(): InnerTubeApi =
            instance ?: synchronized(this) {
                instance ?: InnerTubeApi().also { instance = it }
            }
    }
}
