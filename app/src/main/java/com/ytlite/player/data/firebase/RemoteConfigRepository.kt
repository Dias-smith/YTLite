package com.ytlite.player.data.firebase

import android.content.Context
import android.util.Log
import com.google.firebase.remoteconfig.FirebaseRemoteConfig
import com.google.firebase.remoteconfig.remoteConfigSettings
import kotlinx.coroutines.tasks.await

/**
 * Thin wrapper around Firebase Remote Config.
 * Add default keys here as product needs grow; values can be overridden from the console.
 */
object RemoteConfigRepository {

    private const val TAG = "RemoteConfig"

    /** Minimum fetch interval in production (12h). Debug builds use a short interval. */
    private const val PROD_FETCH_INTERVAL_SECONDS = 12 * 60 * 60L
    private const val DEBUG_FETCH_INTERVAL_SECONDS = 0L

    @Volatile
    private var initialized = false

    fun init(context: Context, isDebuggable: Boolean) {
        if (initialized) return
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
        // Reserved for feature flags; add concrete keys when wiring product toggles.
        Keys.EXAMPLE_FEATURE_ENABLED to false,
    )

    object Keys {
        const val EXAMPLE_FEATURE_ENABLED = "example_feature_enabled"
    }
}
