package com.ytlite.player.data.youtube

import android.util.Log
import android.webkit.CookieManager
import com.ytlite.player.data.network.YoutubeCookieJar

/**
 * Debug-only logging for YouTube cookie bootstrap and subscription fetch.
 * Filter Logcat with tag: YTLite/Youtube
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
}
