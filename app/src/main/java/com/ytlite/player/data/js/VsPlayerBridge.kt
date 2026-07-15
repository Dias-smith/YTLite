package com.ytlite.player.data.js

import android.os.Handler
import android.os.Looper
import android.util.Log
import android.webkit.JavascriptInterface
import android.webkit.WebView
import com.ytlite.player.data.network.InnerTubeConfig
import com.ytlite.player.data.network.YouTubeHttpClient
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.coroutines.Continuation
import kotlin.coroutines.resume

/**
 * Native bridge for extractor.js. HTTP runs on a background executor; callbacks on main thread.
 */
class VsPlayerBridge(
    private val webView: WebView,
    private val httpClient: YouTubeHttpClient = YouTubeHttpClient.getInstance(),
    private val onReady: () -> Unit = {},
    private val onError: (String) -> Unit = {},
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor: ExecutorService = Executors.newFixedThreadPool(HTTP_POOL_SIZE)
    private val pendingMessages = ConcurrentHashMap<String, Continuation<JSONObject>>()
    private val requestResults = ConcurrentHashMap<String, String>()

    @Volatile
    private var cachedVisitorData: String? = null

    @Volatile
    private var visitorDataFetchedAtMs: Long = 0L

    @JavascriptInterface
    fun onExtractorReady() {
        mainHandler.post { onReady() }
    }

    @JavascriptInterface
    fun onExtractorError(message: String) {
        mainHandler.post { onError(message) }
    }

    @JavascriptInterface
    fun getRequestResult(callbackId: String): String {
        return requestResults.remove(callbackId).orEmpty()
    }

    @JavascriptInterface
    fun getVisitorData(): String {
        val now = System.currentTimeMillis()
        val cached = cachedVisitorData
        if (!cached.isNullOrBlank() && now - visitorDataFetchedAtMs < VISITOR_DATA_TTL_MS) {
            return cached
        }
        val fresh = fetchVisitorDataFromYoutube()
        cachedVisitorData = fresh
        visitorDataFetchedAtMs = now
        return fresh
    }

    @JavascriptInterface
    fun requestWithCallback(
        callbackId: String,
        url: String,
        method: String,
        headersJson: String,
        body: String,
        optionsJson: String,
    ) {
        ioExecutor.execute {
            val headers = enrichYouTubeHeaders(url, method, parseHeaders(headersJson))
            Log.d(TAG, "HTTP $method ${url.take(120)} headers=${headers.size}")
            val result = httpClient.request(
                url = url,
                method = method,
                headers = headers,
                body = body.takeIf { it.isNotEmpty() },
            )
            val payload = result.result.orEmpty()
            if (payload.isNotEmpty()) {
                requestResults[callbackId] = payload
            }
            Log.d(
                TAG,
                "HTTP done success=${result.success} code=${result.errCode} " +
                    "bytes=${payload.length} url=${url.take(80)}",
            )
            mainHandler.post {
                val js = buildString {
                    append("window.AndroidBridge_invokeCallback(")
                    append(JSONObject.quote(callbackId))
                    append(",")
                    append(result.success)
                    append(",null,")
                    append(result.errCode)
                    append(",")
                    append(JSONObject.quote(result.errMsg))
                    append(");")
                }
                webView.evaluateJavascript(js, null)
            }
        }
    }

    @JavascriptInterface
    fun sendMessageToNative(messageJson: String) {
        mainHandler.post {
            try {
                val message = JSONObject(messageJson)
                val uid = message.optString("uid")
                val data = message.optJSONObject("data")
                val inner = data?.optJSONObject("data")
                Log.d(
                    TAG,
                    "JS response uid=$uid success=${data?.optBoolean("success")} " +
                        "error=${data?.optString("errorMsg") ?: data?.optString("errorMSG")} " +
                        "hasMusic=${inner?.has("music")}",
                )
                val continuation = pendingMessages.remove(uid) ?: return@post
                continuation.resume(message)
            } catch (e: Exception) {
                Log.e(TAG, "Malformed bridge message", e)
            }
        }
    }

    @JavascriptInterface
    fun queryUserInfo(callbackId: String) {
        invokeSimpleCallback(callbackId, "{}")
    }

    @JavascriptInterface
    fun queryFIRRemoteConfigThen(key: String, callbackId: String) {
        invokeSimpleCallback(callbackId, "")
    }

    fun registerPending(uid: String, continuation: Continuation<JSONObject>) {
        pendingMessages[uid] = continuation
    }

    fun cancelPending(uid: String) {
        pendingMessages.remove(uid)
    }

    fun release() {
        pendingMessages.clear()
        requestResults.clear()
        ioExecutor.shutdown()
    }

    private fun fetchVisitorDataFromYoutube(): String {
        val result = httpClient.request(
            url = "${InnerTubeConfig.BASE_URL}/",
            method = "GET",
            headers = enrichYouTubeHeaders(
                url = "${InnerTubeConfig.BASE_URL}/",
                method = "GET",
                headers = emptyMap(),
            ),
            body = null,
        )
        if (!result.success || result.result.isNullOrBlank()) {
            return ""
        }
        return VISITOR_DATA_REGEX.find(result.result)?.groupValues?.get(1).orEmpty()
    }

    private fun enrichYouTubeHeaders(
        url: String,
        method: String,
        headers: Map<String, String>,
    ): Map<String, String> {
        if (!url.contains("youtube.com")) return headers
        val enriched = headers.toMutableMap()
        if (!enriched.keys.any { it.equals("Accept", ignoreCase = true) }) {
            enriched["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        }
        if (!enriched.keys.any { it.equals("Accept-Language", ignoreCase = true) }) {
            enriched["Accept-Language"] = "en-US,en;q=0.9"
        }
        val userAgent = enriched.entries.firstOrNull { it.key.equals("User-Agent", ignoreCase = true) }?.value
        if (userAgent.isNullOrBlank() || userAgent.contains("Chrome/75")) {
            enriched["User-Agent"] = InnerTubeConfig.USER_AGENT
        }
        if (method.equals("GET", ignoreCase = true)) {
            enriched.putIfAbsent("Sec-Fetch-Mode", "navigate")
            enriched.putIfAbsent("Sec-Fetch-Dest", "document")
        }
        return enriched
    }

    private fun invokeSimpleCallback(callbackId: String, value: String) {
        requestResults[callbackId] = value
        mainHandler.post {
            val js = "window.AndroidBridge_invokeCallback(" +
                "${JSONObject.quote(callbackId)},true,null,0,\"\");"
            webView.evaluateJavascript(js, null)
        }
    }

    private fun parseHeaders(headersJson: String): Map<String, String> {
        if (headersJson.isBlank()) return emptyMap()
        return try {
            val json = JSONObject(headersJson)
            buildMap {
                json.keys().forEach { key ->
                    put(key, json.optString(key))
                }
            }
        } catch (_: Exception) {
            emptyMap()
        }
    }

    companion object {
        private const val TAG = "VsPlayerBridge"
        private const val VISITOR_DATA_TTL_MS = 30 * 60 * 1000L
        private const val HTTP_POOL_SIZE = 4
        private val VISITOR_DATA_REGEX = Regex("\"VISITOR_DATA\":\"([^\"]+)\"")
    }
}
