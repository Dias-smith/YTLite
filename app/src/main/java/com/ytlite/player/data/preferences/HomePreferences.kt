package com.ytlite.player.data.preferences

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.homeDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "home_preferences",
)

class HomePreferences(context: Context) {

    private val dataStore = context.applicationContext.homeDataStore

    val selectedCategoryId: Flow<String?> = dataStore.data.map { prefs ->
        prefs[KEY_SELECTED_CATEGORY_ID]
    }

    suspend fun getSelectedCategoryId(): String? =
        selectedCategoryId.first()

    suspend fun setSelectedCategoryId(categoryId: String) {
        dataStore.edit { it[KEY_SELECTED_CATEGORY_ID] = categoryId }
    }

    companion object {
        private val KEY_SELECTED_CATEGORY_ID = stringPreferencesKey("selected_category_id")

        @Volatile
        private var instance: HomePreferences? = null

        fun getInstance(context: Context): HomePreferences =
            instance ?: synchronized(this) {
                instance ?: HomePreferences(context).also { instance = it }
            }
    }
}
