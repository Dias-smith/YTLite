package com.ytlite.player.data.firebase

import android.content.Context
import android.util.Log
import com.google.firebase.remoteconfig.FirebaseRemoteConfig
import com.google.firebase.remoteconfig.remoteConfigSettings
import kotlinx.coroutines.tasks.await
import org.json.JSONObject

/**
 * Thin wrapper around Firebase Remote Config.
 * Add default keys here as product needs grow; values can be overridden from the console.
 */
object RemoteConfigRepository {

    private const val TAG = "RemoteConfig"

    /** Minimum fetch interval in production (12h). Debug builds use a short interval. */
    private const val PROD_FETCH_INTERVAL_SECONDS = 12 * 60 * 60L
    private const val DEBUG_FETCH_INTERVAL_SECONDS = 0L

    /** Local fallback JSON; effective kickoff stays false until a remote value is activated. */
    private const val ALLOW_KICKOFF_DEFAULT_JSON =
        """{"enable":false,"version":"0.0.0"}"""

    /** Console unit for `ads_interval` is minutes. */
    private const val ADS_INTERVAL_DEFAULT_MINUTES = 30L

    /** Local fallback: percent of duration before local media caching may start. */
    private const val KICKOFF_INTERVAL_DEFAULT_PERCENT = 100L

    @Volatile
    private var initialized = false

    @Volatile
    private var appContext: Context? = null

    fun init(context: Context, isDebuggable: Boolean) {
        if (initialized) return
        appContext = context.applicationContext
        val remoteConfig = FirebaseRemoteConfig.getInstance()
        val settings = remoteConfigSettings {
            minimumFetchIntervalInSeconds = if (isDebuggable) {
                DEBUG_FETCH_INTERVAL_SECONDS
            } else {
                PROD_FETCH_INTERVAL_SECONDS
            }
        }
        remoteConfig.setConfigSettingsAsync(settings)
        remoteConfig.setDefaultsAsync(defaultValues())
        initialized = true
        Log.d(TAG, "Remote Config initialized")
    }

    /**
     * Fetch and activate latest values. Safe to call repeatedly from Application startup.
     */
    suspend fun fetchAndActivate(): Boolean {
        return runCatching {
            val remoteConfig = FirebaseRemoteConfig.getInstance()
            remoteConfig.fetchAndActivate().await()
        }.onFailure { e ->
            Log.w(TAG, "fetchAndActivate failed: ${e.message}")
        }.getOrDefault(false)
    }

    fun getBoolean(key: String): Boolean =
        FirebaseRemoteConfig.getInstance().getBoolean(key)

    fun getString(key: String): String =
        FirebaseRemoteConfig.getInstance().getString(key)

    fun getLong(key: String): Long =
        FirebaseRemoteConfig.getInstance().getLong(key)

    fun getDouble(key: String): Double =
        FirebaseRemoteConfig.getInstance().getDouble(key)

    private fun defaultValues(): Map<String, Any> = mapOf(
        Keys.ALLOW_KICKOFF to ALLOW_KICKOFF_DEFAULT_JSON,
        Keys.ADS_INTERVAL to ADS_INTERVAL_DEFAULT_MINUTES,
        Keys.KICKOFF_INTERVAL to KICKOFF_INTERVAL_DEFAULT_PERCENT,
    )

    object Keys {
        /**
         * JSON: `{ "enable": Bool, "version": "x.y.z" }`.
         * Not fetched → false. App ≥ version → enable. App < version → true.
         */
        const val ALLOW_KICKOFF = "allow_kickoff"

        /** Minutes between two ordinary full-screen ads (app open / interstitial). */
        const val ADS_INTERVAL = "ads_interval"

        /** Percent of track duration (0…100) before local media caching may start. */
        const val KICKOFF_INTERVAL = "kickoff_interval"
    }

    /**
     * When true, play local media cache/download without re-resolving stream URLs.
     *
     * Remote JSON: `{ "enable": Bool, "version": "x.y.z" }`
     * - Not fetched yet (default/static source) → `false`
     * - App version ≥ `version` → `enable`
     * - App version < `version` → `true`
     */
    fun allowKickoff(): Boolean {
        val value = FirebaseRemoteConfig.getInstance().getValue(Keys.ALLOW_KICKOFF)
        if (value.source != FirebaseRemoteConfig.VALUE_SOURCE_REMOTE) return false
        return resolveAllowKickoff(value.asString())
    }

    /**
     * Minimum seconds between two ordinary full-screen ads.
     * Remote `ads_interval` is minutes. Negative → default 30 minutes. Zero means no cooldown.
     */
    fun adsIntervalSeconds(): Long {
        val raw = getLong(Keys.ADS_INTERVAL)
        val minutes = if (raw < 0L) ADS_INTERVAL_DEFAULT_MINUTES else raw
        return minutes * 60L
    }

    /**
     * Percent of track duration (0…100) before local media caching may start.
     * Negative → default `100`. Values above 100 are clamped to 100.
     */
    fun kickoffIntervalPercent(): Long {
        val raw = getLong(Keys.KICKOFF_INTERVAL)
        if (raw < 0L) return KICKOFF_INTERVAL_DEFAULT_PERCENT
        return raw.coerceAtMost(100L)
    }

    private fun resolveAllowKickoff(raw: String): Boolean {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return false
        return runCatching {
            val obj = JSONObject(trimmed)
            val enable = obj.optBoolean("enable", false)
            val gateVersion = obj.optString("version", "0.0.0")
            val current = currentAppVersionName()
            // Older than the gate version → always allow kickoff.
            if (compareSemver(current, gateVersion) < 0) true else enable
        }.getOrDefault(false)
    }

    private fun currentAppVersionName(): String {
        val context = appContext ?: return "0"
        return runCatching {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "0"
        }.getOrDefault("0")
    }

    private fun compareSemver(a: String, b: String): Int {
        val pa = a.split('.').map { it.toIntOrNull() ?: 0 }
        val pb = b.split('.').map { it.toIntOrNull() ?: 0 }
        val n = maxOf(pa.size, pb.size)
        for (i in 0 until n) {
            val x = pa.getOrElse(i) { 0 }
            val y = pb.getOrElse(i) { 0 }
            if (x != y) return x.compareTo(y)
        }
        return 0
    }
}
