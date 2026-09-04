package com.ytlite.player.data.preferences

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.appDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "app_preferences",
)

class AppPreferences(context: Context) {

    private val appContext = context.applicationContext
    private val dataStore = appContext.appDataStore

    val nightModeEnabled: Flow<Boolean> = dataStore.data.map { prefs ->
        prefs[KEY_NIGHT_MODE] ?: DEFAULT_NIGHT_MODE
    }

    val pictureInPictureEnabled: Flow<Boolean> = dataStore.data.map { prefs ->
        prefs[KEY_PICTURE_IN_PICTURE] ?: DEFAULT_PICTURE_IN_PICTURE
    }

    val appLanguage: Flow<String> = dataStore.data.map { prefs ->
        prefs[KEY_APP_LANGUAGE] ?: LANGUAGE_SYSTEM
    }

    suspend fun setNightModeEnabled(enabled: Boolean) {
        dataStore.edit { it[KEY_NIGHT_MODE] = enabled }
        appContext.getSharedPreferences(SYNC_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_NIGHT_MODE.name, enabled)
            .apply()
    }

    suspend fun setPictureInPictureEnabled(enabled: Boolean) {
        // Memory + commit so onPause / auto-enter never reads a stale true after the toggle.
        cachedPictureInPictureEnabled = enabled
        dataStore.edit { it[KEY_PICTURE_IN_PICTURE] = enabled }
        appContext.getSharedPreferences(SYNC_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_PICTURE_IN_PICTURE.name, enabled)
            .commit()
    }

    suspend fun setAppLanguage(language: String) {
        dataStore.edit { it[KEY_APP_LANGUAGE] = language }
        appContext.getSharedPreferences(SYNC_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_APP_LANGUAGE.name, language)
            .apply()
    }

    suspend fun getNightModeEnabledOnce(): Boolean =
        nightModeEnabled.first()

    suspend fun getAppLanguageOnce(): String =
        appLanguage.first()

    companion object {
        const val DEFAULT_NIGHT_MODE = true
        const val DEFAULT_PICTURE_IN_PICTURE = true
        const val LANGUAGE_SYSTEM = "system"
        const val LANGUAGE_EN = "en"
        const val LANGUAGE_ZH = "zh"

        private const val SYNC_PREFS = "app_preferences_sync"
        private val KEY_NIGHT_MODE = booleanPreferencesKey("night_mode_enabled")
        private val KEY_PICTURE_IN_PICTURE = booleanPreferencesKey("picture_in_picture_enabled")
        private val KEY_APP_LANGUAGE = stringPreferencesKey("app_language")

        @Volatile
        private var cachedPictureInPictureEnabled: Boolean? = null

        fun peekLanguage(context: Context): String =
            context.applicationContext
                .getSharedPreferences(SYNC_PREFS, Context.MODE_PRIVATE)
                .getString(KEY_APP_LANGUAGE.name, LANGUAGE_SYSTEM)
                ?: LANGUAGE_SYSTEM

        fun peekNightMode(context: Context): Boolean =
            context.applicationContext
                .getSharedPreferences(SYNC_PREFS, Context.MODE_PRIVATE)
                .getBoolean(KEY_NIGHT_MODE.name, DEFAULT_NIGHT_MODE)

        fun peekPictureInPicture(context: Context): Boolean {
            cachedPictureInPictureEnabled?.let { return it }
            val stored = context.applicationContext
                .getSharedPreferences(SYNC_PREFS, Context.MODE_PRIVATE)
                .getBoolean(KEY_PICTURE_IN_PICTURE.name, DEFAULT_PICTURE_IN_PICTURE)
            cachedPictureInPictureEnabled = stored
            return stored
        }

        @Volatile
        private var instance: AppPreferences? = null

        fun getInstance(context: Context): AppPreferences =
            instance ?: synchronized(this) {
                instance ?: AppPreferences(context).also { instance = it }
            }
    }
}
