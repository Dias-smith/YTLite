package com.ytlite.player.data.network

import android.content.Context
import android.webkit.CookieManager
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.ytlite.player.data.youtube.YoutubeDiagnostics
import kotlinx.coroutines.flow.first
import org.json.JSONArray
import org.json.JSONObject

private val Context.youtubeCookieDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "ytlite_youtube_cookies",
)

/**
 * Persists essential YouTube / Google auth cookies for InnerTube (PRD §3.4).
 * Primary store is [CookieManager]; this backup restores after process death / clearing.
 */
class YoutubeCookieSessionStore(
    context: Context,
) {
    private val appContext = context.applicationContext
    private val dataStore = appContext.youtubeCookieDataStore

    suspend fun saveFromJar() {
        val payload = YoutubeCookieJar.exportAuthCookiesJson()
        dataStore.edit { prefs ->
            if (payload.isNullOrBlank()) {
                prefs.remove(COOKIES_JSON_KEY)
            } else {
                prefs[COOKIES_JSON_KEY] = payload
            }
        }
        YoutubeDiagnostics.d(TAG, "saved cookie backup present=${!payload.isNullOrBlank()}")
    }

    suspend fun restoreIntoCookieManagerAndJar() {
        val json = dataStore.data.first()[COOKIES_JSON_KEY] ?: return
        val restored = YoutubeCookieJar.importAuthCookiesJson(json)
        YoutubeDiagnostics.d(TAG, "restored cookie entries=$restored")
        if (restored > 0) {
            YoutubeCookieJar.syncFromWebView()
        }
    }

    suspend fun clear() {
        dataStore.edit { it.remove(COOKIES_JSON_KEY) }
    }

    companion object {
        private const val TAG = "YoutubeCookieStore"
        private val COOKIES_JSON_KEY = stringPreferencesKey("auth_cookies_json")

        @Volatile
        private var instance: YoutubeCookieSessionStore? = null

        fun getInstance(context: Context): YoutubeCookieSessionStore =
            instance ?: synchronized(this) {
                instance ?: YoutubeCookieSessionStore(context.applicationContext).also {
                    instance = it
                }
            }
    }
}

/** Snapshot helpers used by [YoutubeCookieSessionStore]. */
fun YoutubeCookieJar.exportAuthCookiesJson(): String? {
    val exportNames = setOf(
        "SID", "HSID", "SSID", "APISID", "SAPISID", "LOGIN_INFO",
        "__Secure-1PSID", "__Secure-3PSID",
        "__Secure-1PAPISID", "__Secure-3PAPISID",
        "__Secure-1PSIDCC", "__Secure-3PSIDCC",
    )
    syncFromWebView()
    val array = JSONArray()
    val seen = mutableSetOf<String>()
    for (source in listOf(
        "https://www.youtube.com",
        "https://youtube.com",
        "https://accounts.google.com",
        "https://google.com",
    )) {
        val raw = CookieManager.getInstance().getCookie(source) ?: continue
        raw.split(";").forEach { part ->
            val trimmed = part.trim()
            val eq = trimmed.indexOf('=')
            if (eq <= 0) return@forEach
            val name = trimmed.substring(0, eq)
            val value = trimmed.substring(eq + 1)
            if (name !in exportNames || value.isBlank()) return@forEach
            val key = "$name@$source"
            if (!seen.add(key)) return@forEach
            array.put(
                JSONObject()
                    .put("name", name)
                    .put("value", value)
                    .put("url", source),
            )
        }
    }
    return if (array.length() == 0) null else array.toString()
}

fun YoutubeCookieJar.importAuthCookiesJson(json: String): Int {
    val array = runCatching { JSONArray(json) }.getOrNull() ?: return 0
    val manager = CookieManager.getInstance()
    manager.setAcceptCookie(true)
    var count = 0
    for (index in 0 until array.length()) {
        val item = array.optJSONObject(index) ?: continue
        val name = item.optString("name")
        val value = item.optString("value")
        val url = item.optString("url")
        if (name.isBlank() || value.isBlank() || url.isBlank()) continue
        manager.setCookie(url, "$name=$value; Path=/; Secure")
        count++
    }
    manager.flush()
    syncFromWebView()
    return count
}
