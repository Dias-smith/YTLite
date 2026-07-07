package com.ytlite.player.data.network

import com.ytlite.player.data.youtube.YoutubeDiagnostics
import java.security.MessageDigest

/**
 * Builds YouTube authenticated request headers from synced session cookies.
 *
 * SAPISID lives on `.google.com` and is not sent to youtube.com by OkHttp automatically;
 * InnerTube expects it via the `Authorization: SAPISIDHASH …` header.
 */
object YoutubeAuthHeaders {

    private const val ORIGIN = "https://www.youtube.com"

    fun buildAuthenticatedHeaders(): Map<String, String> {
        val headers = mutableMapOf(
            "Origin" to ORIGIN,
            "X-Origin" to ORIGIN,
            "Referer" to "$ORIGIN/",
        )
        buildAuthorizationHeader()?.let { headers["Authorization"] = it }
        return headers
    }

    fun buildAuthorizationHeader(): String? {
        val sapisid = YoutubeCookieJar.findCookieValue("SAPISID")
            ?: YoutubeCookieJar.findCookieValue("__Secure-3PAPISID")
            ?: YoutubeCookieJar.findCookieValue("__Secure-1PAPISID")
        if (sapisid == null) {
            YoutubeDiagnostics.w("AuthHeaders", "buildAuthorizationHeader: no SAPISID source cookie found")
            return null
        }
        YoutubeDiagnostics.d(
            "AuthHeaders",
            "buildAuthorizationHeader: using cookie source " +
                when {
                    YoutubeCookieJar.findCookieValue("SAPISID") != null -> "SAPISID"
                    YoutubeCookieJar.findCookieValue("__Secure-3PAPISID") != null -> "__Secure-3PAPISID"
                    else -> "__Secure-1PAPISID"
                },
        )
        val timestamp = System.currentTimeMillis() / 1000
        val digest = MessageDigest.getInstance("SHA-1")
            .digest("$timestamp $sapisid $ORIGIN".toByteArray())
        val hash = digest.joinToString("") { byte -> "%02x".format(byte) }
        return "SAPISIDHASH ${timestamp}_$hash"
    }
}
