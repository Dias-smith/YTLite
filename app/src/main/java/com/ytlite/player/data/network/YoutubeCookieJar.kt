package com.ytlite.player.data.network

import android.webkit.CookieManager
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Shared cookie store synced from WebView CookieManager for authenticated InnerTube calls.
 */
object YoutubeCookieJar : CookieJar {

    private val cookies = CopyOnWriteArrayList<Cookie>()

    override fun saveFromResponse(url: HttpUrl, responseCookies: List<Cookie>) {
        cookies.removeAll { existing ->
            responseCookies.any { it.name == existing.name && it.domain == existing.domain }
        }
        cookies.addAll(responseCookies)
    }

    override fun loadForRequest(url: HttpUrl): List<Cookie> =
        cookies.filter { it.matches(url) }

    fun syncFromWebView() {
        val manager = CookieManager.getInstance()
        val domains = listOf(
            "https://www.youtube.com",
            "https://youtube.com",
            "https://accounts.google.com",
        )
        val parsed = domains.flatMap { domain ->
            manager.getCookie(domain)
                ?.split(";")
                ?.mapNotNull { part ->
                    val trimmed = part.trim()
                    val eq = trimmed.indexOf('=')
                    if (eq <= 0) return@mapNotNull null
                    val name = trimmed.substring(0, eq)
                    val value = trimmed.substring(eq + 1)
                    Cookie.Builder()
                        .name(name)
                        .value(value)
                        .domain(
                            domain.removePrefix("https://").removePrefix("http://").trimEnd('/'),
                        )
                        .build()
                }
                .orEmpty()
        }
        cookies.clear()
        cookies.addAll(parsed)
    }

    fun clear() {
        cookies.clear()
    }

    fun hasAuthCookies(): Boolean =
        cookies.any { it.name == "SID" || it.name == "SAPISID" || it.name == "__Secure-3PSID" }
}
