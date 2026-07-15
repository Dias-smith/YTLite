package com.ytlite.player.data.preferences

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.floatPreferencesKey
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import com.ytlite.player.playback.PlaybackSpeeds

private val Context.playbackDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "playback_preferences",
)

class PlaybackPreferences(context: Context) {

    private val dataStore = context.applicationContext.playbackDataStore

    val playbackSpeed: Flow<Float> = dataStore.data.map { prefs ->
        PlaybackSpeeds.coerce(prefs[KEY_PLAYBACK_SPEED] ?: DEFAULT_SPEED)
    }

    val preferredItag: Flow<Int?> = dataStore.data.map { prefs ->
        prefs[KEY_PREFERRED_ITAG]
    }

    suspend fun setPlaybackSpeed(speed: Float) {
        dataStore.edit { it[KEY_PLAYBACK_SPEED] = PlaybackSpeeds.coerce(speed) }
    }

    suspend fun setPreferredItag(itag: Int?) {
        dataStore.edit { prefs ->
            if (itag == null) {
                prefs.remove(KEY_PREFERRED_ITAG)
            } else {
                prefs[KEY_PREFERRED_ITAG] = itag
            }
        }
    }

    companion object {
        const val DEFAULT_SPEED = PlaybackSpeeds.DEFAULT

        private val KEY_PLAYBACK_SPEED = floatPreferencesKey("playback_speed")
        private val KEY_PREFERRED_ITAG = intPreferencesKey("preferred_itag")

        @Volatile
        private var instance: PlaybackPreferences? = null

        fun getInstance(context: Context): PlaybackPreferences =
            instance ?: synchronized(this) {
                instance ?: PlaybackPreferences(context).also { instance = it }
            }
    }
}
