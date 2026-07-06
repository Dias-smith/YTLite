package com.ytlite.player.data.auth

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import java.util.UUID

private val Context.sessionDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "ytlite_session",
)

class GuestSessionStore(
    context: Context,
) {
    private val dataStore = context.applicationContext.sessionDataStore

    val guestIdFlow: Flow<String> = dataStore.data.map { prefs ->
        prefs[GUEST_ID_KEY] ?: ""
    }

    val supabaseUserIdFlow: Flow<String?> = dataStore.data.map { prefs ->
        prefs[SUPABASE_USER_ID_KEY]
    }

    suspend fun ensureGuestId(): String {
        val existing = dataStore.data.first()[GUEST_ID_KEY]
        if (!existing.isNullOrBlank()) return existing
        val newId = UUID.randomUUID().toString()
        dataStore.edit { it[GUEST_ID_KEY] = newId }
        return newId
    }

    suspend fun getGuestId(): String? = dataStore.data.first()[GUEST_ID_KEY]

    suspend fun setSupabaseUserId(userId: String?) {
        dataStore.edit { prefs ->
            if (userId.isNullOrBlank()) {
                prefs.remove(SUPABASE_USER_ID_KEY)
            } else {
                prefs[SUPABASE_USER_ID_KEY] = userId
            }
        }
    }

    suspend fun rotateGuestId(): String {
        val newId = UUID.randomUUID().toString()
        dataStore.edit { it[GUEST_ID_KEY] = newId }
        return newId
    }

    companion object {
        private val GUEST_ID_KEY = stringPreferencesKey("guest_id")
        private val SUPABASE_USER_ID_KEY = stringPreferencesKey("supabase_user_id")
    }
}
