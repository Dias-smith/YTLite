package com.ytlite.player.data.youtube

import android.util.Log
import android.webkit.CookieManager
import com.ytlite.player.data.network.YoutubeCookieJar

/**
 * Debug-only logging for YouTube cookie bootstrap and subscription fetch.
 * Filter Logcat with tag: YTLite/Youtube
 *
 * Playlist fetch trace: filter `Playlists/` in message or step.
 */
object YoutubeDiagnostics {

    private const val TAG = "YTLite/Youtube"

    fun d(step: String, message: String) {
        Log.d(TAG, "[$step] $message")
    }

    fun w(step: String, message: String, throwable: Throwable? = null) {
        if (throwable != null) {
            Log.w(TAG, "[$step] $message", throwable)
        } else {
            Log.w(TAG, "[$step] $message")
        }
    }

    fun e(step: String, message: String, throwable: Throwable? = null) {
        if (throwable != null) {
            Log.e(TAG, "[$step] $message", throwable)
        } else {
            Log.e(TAG, "[$step] $message")
        }
    }

    fun logCookieJarState(step: String) {
        d(
            step,
            "jarCount=${YoutubeCookieJar.debugJarCookieCount()} " +
                "names=${YoutubeCookieJar.debugJarCookieNames()} " +
                "googleAuth=${YoutubeCookieJar.hasGoogleAuthCookies()} " +
                "apiSid=${YoutubeCookieJar.hasYoutubeApiSidCookie()} " +
                "ytSession=${YoutubeCookieJar.hasYoutubeSessionCookies()} " +
                "hasAuth=${YoutubeCookieJar.hasAuthCookies()}",
        )
    }

    fun logWebViewRawCookies(step: String) {
        val sources = listOf(
            "https://m.youtube.com",
            "https://www.youtube.com",
            "https://accounts.google.com",
            "https://google.com",
        )
        sources.forEach { url ->
            val raw = CookieManager.getInstance().getCookie(url)
            val names = raw
                ?.split(";")
                ?.mapNotNull { part ->
                    val eq = part.trim().indexOf('=')
                    if (eq <= 0) null else part.trim().substring(0, eq)
                }
                ?.sorted()
                ?: emptyList()
            d(step, "webview url=$url rawPresent=${!raw.isNullOrBlank()} names=$names")
        }
    }

    fun logPlaylistsFetchStart(
        step: String,
        ownerKey: String?,
        sessionType: String,
        apiConfigured: Boolean,
        needsReauth: Boolean,
        tokenPresent: Boolean,
        tokenLength: Int,
        tokenSource: String,
    ) {
        d(
            step,
            "start ownerKey=$ownerKey session=$sessionType apiConfigured=$apiConfigured " +
                "needsReauth=$needsReauth tokenPresent=$tokenPresent tokenLen=$tokenLength tokenSource=$tokenSource",
        )
    }

    fun logPlaylistsFetchOutcome(step: String, outcome: String, detail: String) {
        d(step, "outcome=$outcome $detail")
    }

    fun logPlaylistsListRequest(step: String, pageToken: String?, maxResults: Int) {
        d(step, "request playlists.list mine=true pageToken=${pageToken ?: "null"} maxResults=$maxResults")
    }

    fun logPlaylistsListResponse(
        step: String,
        pageToken: String?,
        httpCode: Int,
        success: Boolean,
        bodySnippet: String,
    ) {
        val pageInfo = runCatching {
            val json = org.json.JSONObject(bodySnippet)
            val pageInfoObj = json.optJSONObject("pageInfo")
            "totalResults=${pageInfoObj?.optInt("totalResults")} resultsPerPage=${pageInfoObj?.optInt("resultsPerPage")}"
        }.getOrElse { "pageInfo=unavailable" }
        val itemSummaries = runCatching {
            val json = org.json.JSONObject(bodySnippet)
            val items = json.optJSONArray("items") ?: return@runCatching "items=null"
            if (items.length() == 0) return@runCatching "items=[]"
            buildList {
                for (index in 0 until items.length()) {
                    val item = items.optJSONObject(index) ?: continue
                    val id = item.optString("id")
                    val title = item.optJSONObject("snippet")?.optString("title").orEmpty()
                    val itemCount = item.optJSONObject("contentDetails")?.optString("itemCount")
                    add("id=$id title=$title itemCount=$itemCount")
                }
            }.joinToString(prefix = "[", postfix = "]")
        }.getOrElse { "items=parse_error" }
        d(
            step,
            "response pageToken=${pageToken ?: "null"} httpCode=$httpCode success=$success " +
                "$pageInfo $itemSummaries body=${bodySnippet.take(1200)}",
        )
    }

    fun logPlaylistsParsed(
        step: String,
        rawItemCount: Int,
        parsedCount: Int,
        skippedCount: Int,
        summaries: List<String>,
    ) {
        d(
            step,
            "parsed rawItems=$rawItemCount parsed=$parsedCount skipped=$skippedCount playlists=$summaries",
        )
    }

    fun logUnifiedPlaylistsSnapshot(
        step: String,
        ownerKey: String,
        localCount: Int,
        youtubeCount: Int,
        youtubeIds: List<String>,
    ) {
        d(
            step,
            "snapshot ownerKey=$ownerKey local=$localCount youtube=$youtubeCount youtubePlaylists=$youtubeIds",
        )
    }
}
