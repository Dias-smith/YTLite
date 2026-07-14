package com.ytlite.player.data.network

import com.ytlite.player.data.youtube.YoutubeDiagnostics
import org.json.JSONObject

class InnerTubeApi(
    private val httpClient: YouTubeHttpClient = YouTubeHttpClient.getInstance(),
) {

    fun browseHome(continuation: String? = null): JSONObject {
        return browse(
            InnerTubeConfig.BROWSE_ID_HOME,
            label = "browse_home",
            continuation = continuation,
        )
    }

    fun browseLibraryPlaylists(): JSONObject {
        return browse(
            browseId = InnerTubeConfig.BROWSE_ID_LIBRARY,
            label = "browse_library",
            authenticated = true,
        )
    }

    fun browsePlaylistItems(
        youtubePlaylistId: String,
        continuation: String? = null,
    ): JSONObject {
        val browseId = if (youtubePlaylistId.startsWith("VL")) {
            youtubePlaylistId
        } else {
            "VL$youtubePlaylistId"
        }
        return browse(browseId, label = "browse_playlist", continuation = continuation)
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

    private fun resolveBrowseResponse(
        response: JSONObject,
        label: String,
        authenticated: Boolean,
        depth: Int,
    ): JSONObject {
        if (depth >= MAX_NAVIGATE_DEPTH) return response

        val actions = response.optJSONArray("onResponseReceivedActions")
        for (index in 0 until (actions?.length() ?: 0)) {
            val navigate = actions?.optJSONObject(index)?.optJSONObject("navigateAction") ?: continue
            val browseEndpoint = navigate
                .optJSONObject("endpoint")
                ?.optJSONObject("browseEndpoint")
                ?: continue

            val targetBrowseId = browseEndpoint.optString("browseId")
            if (targetBrowseId.isBlank()) continue

            val params = browseEndpoint.optString("params").takeIf { it.isNotBlank() }
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
    ): JSONObject = search(query = query, params = null, continuation = continuation)

    fun search(
        query: String,
        params: String? = null,
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
                if (!params.isNullOrBlank()) {
                    put("params", params)
                }
            }
        }
        return post(
            url = InnerTubeConfig.SEARCH_URL,
            body = body,
            label = "search",
            client = InnerTubeConfig.FEED_CLIENT,
        )
    }

    /**
     * YouTube searchbox autocomplete via Google Suggest ([ds=yt]).
     * Returns related query strings for [query], not video/channel results.
     */
    fun fetchSuggestQueries(query: String): List<String> {
        val encoded = java.net.URLEncoder.encode(query.trim(), Charsets.UTF_8.name())
        val url = "${InnerTubeConfig.SUGGEST_QUERIES_BASE_URL}&q=$encoded"
        val result = httpClient.request(
            url = url,
            method = "GET",
            headers = mapOf(
                "User-Agent" to InnerTubeConfig.USER_AGENT,
                "Accept" to "application/json",
            ),
            body = null,
        )
        if (!result.success || result.result.isNullOrBlank()) {
            YoutubeDiagnostics.e(TAG, "suggest_queries http failed code=${result.errCode} msg=${result.errMsg}")
            return emptyList()
        }
        return parseSuggestQueriesPayload(result.result)
    }

    private fun parseSuggestQueriesPayload(payload: String): List<String> {
        return runCatching {
            val root = org.json.JSONArray(payload)
            val items = root.optJSONArray(1) ?: return emptyList()
            buildList {
                for (index in 0 until items.length()) {
                    val text = items.optString(index).trim()
                    if (text.isNotBlank()) add(text)
                }
            }
        }.getOrElse { emptyList() }
    }

    fun fetchWatchNext(videoId: String): JSONObject {
        val body = JSONObject().apply {
            put("context", buildClientContext(InnerTubeConfig.FEED_CLIENT))
            put("videoId", videoId)
            put("racyCheckOk", true)
            put("contentCheckOk", true)
        }
        return post(
            url = InnerTubeConfig.NEXT_URL,
            body = body,
            label = "watch_next",
            client = InnerTubeConfig.FEED_CLIENT,
            origin = InnerTubeConfig.BASE_URL,
        )
    }

    /**
     * YouTube Music radio queue for [videoId] (`RDAMVM…`), returns ~50 related tracks.
     */
    fun fetchMusicRadioNext(videoId: String): JSONObject {
        val body = JSONObject().apply {
            put("context", buildClientContext(InnerTubeConfig.MUSIC_CLIENT))
            put("videoId", videoId)
            put("playlistId", "RDAMVM$videoId")
            put("racyCheckOk", true)
            put("contentCheckOk", true)
        }
        return post(
            url = InnerTubeConfig.MUSIC_NEXT_URL,
            body = body,
            label = "music_radio_next",
            client = InnerTubeConfig.MUSIC_CLIENT,
            origin = InnerTubeConfig.MUSIC_BASE_URL,
        )
    }

    /**
     * YouTube Music browse (e.g. [FEmusic_new_releases_albums](https://music.youtube.com/new_releases/albums)).
     */
    fun browseMusic(
        browseId: String,
        params: String? = null,
        continuation: String? = null,
    ): JSONObject {
        val body = JSONObject().apply {
            put("context", buildClientContext(InnerTubeConfig.MUSIC_CLIENT))
            if (!continuation.isNullOrBlank()) {
                put("continuation", continuation)
            } else {
                put("browseId", browseId)
                if (!params.isNullOrBlank()) {
                    put("params", params)
                }
            }
        }
        return post(
            url = InnerTubeConfig.MUSIC_BROWSE_URL,
            body = body,
            label = "music_browse",
            client = InnerTubeConfig.MUSIC_CLIENT,
            origin = InnerTubeConfig.MUSIC_BASE_URL,
        )
    }

    fun browseExplore(
        browseId: String,
        params: String? = null,
        continuation: String? = null,
    ): JSONObject {
        if (!continuation.isNullOrBlank()) {
            return browse(browseId, label = "browse_explore", continuation = continuation)
        }
        val body = buildBrowseBody(browseId, params)
        return postBrowseBody(body = body, label = "browse_explore", authenticated = false)
    }

    private fun post(
        url: String,
        body: JSONObject,
        label: String,
        client: InnerTubeClientType,
        authenticated: Boolean = false,
        origin: String = InnerTubeConfig.BASE_URL,
    ): JSONObject {
        val headers = mutableMapOf(
            "Content-Type" to "application/json",
            "User-Agent" to InnerTubeConfig.USER_AGENT,
            "X-YouTube-Client-Name" to client.clientNameHeader,
            "X-YouTube-Client-Version" to client.clientVersion,
            "Origin" to origin,
            "Referer" to "$origin/",
        )
        if (authenticated && YoutubeCookieJar.hasAuthCookies()) {
            headers.putAll(YoutubeAuthHeaders.buildAuthenticatedHeaders())
        }
        val result = httpClient.request(
            url = url,
            method = "POST",
            headers = headers,
            body = body.toString(),
        )
        if (!result.success || result.result.isNullOrBlank()) {
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
