package com.ytlite.player.data.preferences

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.downloadDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "download_preferences",
)

enum class DefaultDownloadFormat {
    AskEachTime,
    AudioFast,
    Video360,
    Video720,
}

class DownloadPreferences(context: Context) {

    private val dataStore = context.applicationContext.downloadDataStore

    val threadCount: Flow<Int> = dataStore.data.map { prefs ->
        (prefs[KEY_THREAD_COUNT] ?: DEFAULT_THREAD_COUNT).coerceIn(1, 8)
    }

    val resumeEnabled: Flow<Boolean> = dataStore.data.map { prefs ->
        prefs[KEY_RESUME_ENABLED] ?: true
    }

    val wifiOnly: Flow<Boolean> = dataStore.data.map { prefs ->
        prefs[KEY_WIFI_ONLY] ?: false
    }

    val defaultFormat: Flow<DefaultDownloadFormat> = dataStore.data.map { prefs ->
        runCatching {
            DefaultDownloadFormat.valueOf(prefs[KEY_DEFAULT_FORMAT] ?: DefaultDownloadFormat.AskEachTime.name)
        }.getOrDefault(DefaultDownloadFormat.AskEachTime)
    }

    suspend fun setThreadCount(count: Int) {
        dataStore.edit { it[KEY_THREAD_COUNT] = count.coerceIn(1, 8) }
    }

    suspend fun setResumeEnabled(enabled: Boolean) {
        dataStore.edit { it[KEY_RESUME_ENABLED] = enabled }
    }

    suspend fun setWifiOnly(enabled: Boolean) {
        dataStore.edit { it[KEY_WIFI_ONLY] = enabled }
    }

    suspend fun setDefaultFormat(format: DefaultDownloadFormat) {
        dataStore.edit { it[KEY_DEFAULT_FORMAT] = format.name }
    }

    suspend fun peekThreadCount(): Int = threadCount.first()
    suspend fun peekResumeEnabled(): Boolean = resumeEnabled.first()
    suspend fun peekWifiOnly(): Boolean = wifiOnly.first()
    suspend fun peekDefaultFormat(): DefaultDownloadFormat = defaultFormat.first()

    fun preferredItagFor(format: DefaultDownloadFormat): Int? = when (format) {
        DefaultDownloadFormat.AskEachTime -> null
        DefaultDownloadFormat.AudioFast -> 140
        DefaultDownloadFormat.Video360 -> 18
        DefaultDownloadFormat.Video720 -> 22
    }

    companion object {
        const val DEFAULT_THREAD_COUNT = 2

        private val KEY_THREAD_COUNT = intPreferencesKey("thread_count")
        private val KEY_RESUME_ENABLED = booleanPreferencesKey("resume_enabled")
        private val KEY_WIFI_ONLY = booleanPreferencesKey("wifi_only")
        private val KEY_DEFAULT_FORMAT = stringPreferencesKey("default_format")

        @Volatile
        private var instance: DownloadPreferences? = null

        fun getInstance(context: Context): DownloadPreferences =
            instance ?: synchronized(this) {
                instance ?: DownloadPreferences(context).also { instance = it }
            }
    }
}
