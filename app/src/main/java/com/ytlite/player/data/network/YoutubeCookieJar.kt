package com.ytlite.player.data.network

import android.webkit.CookieManager
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.HttpUrl
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Shared cookie store synced from WebView CookieManager for authenticated InnerTube calls.
 */
object YoutubeCookieJar : CookieJar {

    private val cookies = CopyOnWriteArrayList<Cookie>()

    private val cookieSources = listOf(
        CookieSource("https://m.youtube.com", "youtube.com"),
        CookieSource("https://www.youtube.com", "www.youtube.com", hostOnly = true),
        CookieSource("https://youtube.com", "youtube.com"),
        CookieSource("https://accounts.google.com", "google.com"),
        CookieSource("https://google.com", "google.com"),
    )

    override fun saveFromResponse(url: HttpUrl, responseCookies: List<Cookie>) {
        cookies.removeAll { existing ->
            responseCookies.any { it.name == existing.name && it.domain == existing.domain }
        }
        cookies.addAll(responseCookies)
    }

    override fun loadForRequest(url: HttpUrl): List<Cookie> =
        cookies.filter { it.matches(url) }

    fun syncFromWebView() {
        CookieManager.getInstance().flush()
        val parsed = cookieSources.flatMap { source ->
            parseCookiesForDomain(
                url = source.url,
                domain = source.cookieDomain,
                hostOnly = source.hostOnly,
            )
        }
        cookies.clear()
        cookies.addAll(parsed)
        mirrorAuthCookiesToYoutubeDomain()
    }

    /**
     * WebView stores Google auth cookies on google.com; mirror them to youtube.com so OkHttp
     * attaches them to InnerTube requests on www.youtube.com.
     */
    private fun mirrorAuthCookiesToYoutubeDomain() {
        val mirrorNames = setOf(
            "SID", "HSID", "SSID", "APISID", "SAPISID", "LOGIN_INFO",
            "__Secure-1PSID", "__Secure-3PSID",
            "__Secure-1PAPISID", "__Secure-3PAPISID",
            "__Secure-1PSIDCC", "__Secure-3PSIDCC",
        )
        val sources = cookies.filter { cookie ->
            cookie.domain == "google.com" && cookie.name in mirrorNames
        }
        for (source in sources) {
            if (cookies.any { it.name == source.name && it.domain == "youtube.com" }) continue
            val builder = Cookie.Builder()
                .name(source.name)
                .value(source.value)
                .domain("youtube.com")
                .path(source.path.ifBlank { "/" })
            if (source.secure) builder.secure()
            cookies.add(builder.build())
        }
    }

    fun persistFromWebView() {
        syncFromWebView()
        CookieManager.getInstance().flush()
    }

    fun clear() {
        cookies.clear()
    }

    fun findCookieValue(name: String): String? =
        cookies.firstOrNull { it.name == name }?.value

    fun hasGoogleAuthCookies(): Boolean =
        listOf("SAPISID", "__Secure-3PAPISID", "__Secure-1PAPISID", "SID")
            .any { findCookieValue(it) != null }

    fun hasYoutubeApiSidCookie(): Boolean =
        findCookieValue("__Secure-3PAPISID") != null

    fun hasAuthCookies(): Boolean =
        hasYoutubeApiSidCookie() || hasYoutubeSessionCookies()

    fun hasYoutubeSessionCookies(): Boolean =
        listOf("__Secure-3PSID", "__Secure-1PSID", "SID", "LOGIN_INFO")
            .any { findCookieValue(it) != null }

    /** Debug: cookie names currently held in the in-memory jar. */
    fun debugJarCookieNames(): List<String> =
        cookies.map { "${it.name}@${it.domain}" }.sorted()

    fun debugJarCookieCount(): Int = cookies.size

    /** Debug: how many cookies OkHttp would attach for a youtube.com browse request. */
    fun debugCookiesForYoutubeRequest(): List<String> {
        val url = "https://www.youtube.com/youtubei/v1/browse".toHttpUrl()
        return loadForRequest(url).map { it.name }.sorted()
    }

    private fun parseCookiesForDomain(
        url: String,
        domain: String,
        hostOnly: Boolean = false,
    ): List<Cookie> {
        val raw = CookieManager.getInstance().getCookie(url) ?: return emptyList()
        val canonicalDomain = domain.trimStart('.')
        return raw.split(";").mapNotNull { part ->
            val trimmed = part.trim()
            val eq = trimmed.indexOf('=')
            if (eq <= 0) return@mapNotNull null
            val name = trimmed.substring(0, eq)
            val value = trimmed.substring(eq + 1)
            if (name.isBlank() || value.isBlank()) return@mapNotNull null

            val builder = Cookie.Builder()
                .name(name)
                .value(value)
                .path("/")

            when {
                name.startsWith("__Host-") -> builder.hostOnlyDomain(canonicalDomain).secure()
                hostOnly -> builder.hostOnlyDomain(canonicalDomain)
                else -> builder.domain(canonicalDomain)
            }

            if (name.startsWith("__Secure-")) {
                builder.secure()
            }
            builder.build()
        }
    }

    private data class CookieSource(
        val url: String,
        val cookieDomain: String,
        val hostOnly: Boolean = false,
    )
}
