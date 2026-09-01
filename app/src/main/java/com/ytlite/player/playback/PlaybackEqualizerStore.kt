package com.ytlite.player.playback

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.floatPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

private val Context.equalizerDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "playback_equalizer",
)

data class PlaybackEqualizerState(
    val isEnabled: Boolean = false,
    val selectedPresetId: String = "flat",
    val usesCustomBands: Boolean = false,
    val customBandGainsDb: FloatArray = PlaybackEqualizerCatalog.flatGains(),
    val streamEligible: Boolean = true,
    val volumeBoostPercent: Float = PlaybackEqualizerCatalog.DEFAULT_VOLUME_BOOST_PERCENT,
) {
    val activeGainsDb: FloatArray
        get() = if (
            usesCustomBands ||
            PlaybackEqualizerCatalog.isCustomPreset(selectedPresetId)
        ) {
            customBandGainsDb
        } else {
            PlaybackEqualizerCatalog.preset(selectedPresetId)?.gainsDb?.toFloatArray()
                ?: PlaybackEqualizerCatalog.flatGains()
        }

    val volumeBoostMultiplier: Float
        get() = PlaybackEqualizerCatalog.volumeBoostMultiplier(volumeBoostPercent)

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is PlaybackEqualizerState) return false
        return isEnabled == other.isEnabled &&
            selectedPresetId == other.selectedPresetId &&
            usesCustomBands == other.usesCustomBands &&
            customBandGainsDb.contentEquals(other.customBandGainsDb) &&
            streamEligible == other.streamEligible &&
            volumeBoostPercent == other.volumeBoostPercent
    }

    override fun hashCode(): Int {
        var result = isEnabled.hashCode()
        result = 31 * result + selectedPresetId.hashCode()
        result = 31 * result + usesCustomBands.hashCode()
        result = 31 * result + customBandGainsDb.contentHashCode()
        result = 31 * result + streamEligible.hashCode()
        result = 31 * result + volumeBoostPercent.hashCode()
        return result
    }
}

class PlaybackEqualizerStore private constructor(context: Context) {
    private val appContext = context.applicationContext
    private val dataStore = appContext.equalizerDataStore
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private val _state = MutableStateFlow(PlaybackEqualizerState())
    val state: StateFlow<PlaybackEqualizerState> = _state.asStateFlow()

    init {
        PlaybackEqualizerCatalog.ensureLoaded(appContext)
        scope.launch {
            _state.value = dataStore.data.first().toState()
            PlaybackEqualizerHolder.apply(_state.value)
        }
    }

    fun setEnabled(enabled: Boolean) {
        scope.launch {
            dataStore.edit { it[KEY_ENABLED] = enabled }
            _state.value = _state.value.copy(isEnabled = enabled)
            PlaybackEqualizerHolder.apply(_state.value)
        }
    }

    fun selectPreset(id: String) {
        scope.launch {
            val usesCustom = PlaybackEqualizerCatalog.isCustomPreset(id)
            dataStore.edit { prefs ->
                prefs[KEY_PRESET] = id
                prefs[KEY_USES_CUSTOM] = usesCustom
            }
            _state.value = _state.value.copy(
                selectedPresetId = id,
                usesCustomBands = usesCustom,
            )
            PlaybackEqualizerHolder.apply(_state.value)
        }
    }

    fun setCustomBand(index: Int, gainDb: Float) {
        if (index !in 0 until PlaybackEqualizerCatalog.BAND_COUNT) return
        scope.launch {
            val seededGains = if (!_state.value.usesCustomBands) {
                _state.value.activeGainsDb.copyOf()
            } else {
                _state.value.customBandGainsDb.copyOf()
            }
            seededGains[index] = gainDb.coerceIn(
                PlaybackEqualizerCatalog.MIN_GAIN_DB,
                PlaybackEqualizerCatalog.MAX_GAIN_DB,
            )
            dataStore.edit { prefs ->
                prefs[KEY_PRESET] = PlaybackEqualizerCatalog.CUSTOM_PRESET_ID
                prefs[KEY_USES_CUSTOM] = true
                prefs[KEY_CUSTOM_GAINS] = seededGains.joinToString(",")
            }
            _state.value = _state.value.copy(
                selectedPresetId = PlaybackEqualizerCatalog.CUSTOM_PRESET_ID,
                usesCustomBands = true,
                customBandGainsDb = seededGains,
            )
            PlaybackEqualizerHolder.apply(_state.value)
        }
    }

    fun resetCustomBands() {
        scope.launch {
            val flat = PlaybackEqualizerCatalog.flatGains()
            dataStore.edit { prefs ->
                prefs[KEY_PRESET] = "flat"
                prefs[KEY_USES_CUSTOM] = false
                prefs[KEY_CUSTOM_GAINS] = flat.joinToString(",")
            }
            _state.value = _state.value.copy(
                selectedPresetId = "flat",
                usesCustomBands = false,
                customBandGainsDb = flat,
            )
            PlaybackEqualizerHolder.apply(_state.value)
        }
    }

    fun setVolumeBoostPercent(percent: Float) {
        val clamped = percent.coerceIn(
            PlaybackEqualizerCatalog.MIN_VOLUME_BOOST_PERCENT,
            PlaybackEqualizerCatalog.MAX_VOLUME_BOOST_PERCENT,
        )
        scope.launch {
            dataStore.edit { it[KEY_VOLUME_BOOST] = clamped }
            _state.value = _state.value.copy(volumeBoostPercent = clamped)
            PlaybackEqualizerHolder.apply(_state.value)
        }
    }

    fun refreshStream(streamUrl: String?) {
        val eligible = PlaybackEqualizerSupport.isEligibleStreamUrl(streamUrl)
        _state.value = _state.value.copy(streamEligible = eligible)
        PlaybackEqualizerHolder.apply(_state.value)
    }

    private fun Preferences.toState(): PlaybackEqualizerState {
        val customRaw = this[KEY_CUSTOM_GAINS].orEmpty()
        val customGains = if (customRaw.isNotBlank()) {
            customRaw.split(",").mapNotNull { it.toFloatOrNull() }.toFloatArray()
        } else {
            PlaybackEqualizerCatalog.flatGains()
        }
        val normalizedCustom = if (customGains.size == PlaybackEqualizerCatalog.BAND_COUNT) {
            customGains
        } else {
            PlaybackEqualizerCatalog.flatGains()
        }
        val storedPreset = this[KEY_PRESET] ?: "flat"
        val usesCustom = this[KEY_USES_CUSTOM] ?: false
        val selectedPreset = if (usesCustom) {
            PlaybackEqualizerCatalog.CUSTOM_PRESET_ID
        } else {
            storedPreset
        }
        return PlaybackEqualizerState(
            isEnabled = this[KEY_ENABLED] ?: false,
            selectedPresetId = selectedPreset,
            usesCustomBands = usesCustom || PlaybackEqualizerCatalog.isCustomPreset(selectedPreset),
            customBandGainsDb = normalizedCustom,
            volumeBoostPercent = (this[KEY_VOLUME_BOOST] ?: PlaybackEqualizerCatalog.DEFAULT_VOLUME_BOOST_PERCENT)
                .coerceIn(
                    PlaybackEqualizerCatalog.MIN_VOLUME_BOOST_PERCENT,
                    PlaybackEqualizerCatalog.MAX_VOLUME_BOOST_PERCENT,
                ),
        )
    }

    companion object {
        private val KEY_ENABLED = booleanPreferencesKey("enabled")
        private val KEY_PRESET = stringPreferencesKey("preset")
        private val KEY_USES_CUSTOM = booleanPreferencesKey("uses_custom")
        private val KEY_CUSTOM_GAINS = stringPreferencesKey("custom_gains")
        private val KEY_VOLUME_BOOST = floatPreferencesKey("volume_boost")

        @Volatile
        private var instance: PlaybackEqualizerStore? = null

        fun getInstance(context: Context): PlaybackEqualizerStore =
            instance ?: synchronized(this) {
                instance ?: PlaybackEqualizerStore(context.applicationContext).also { instance = it }
            }
    }
}

object PlaybackEqualizerHolder {
    val processor = PlaybackEqualizerAudioProcessor()

    fun apply(state: PlaybackEqualizerState) {
        val eligible = state.streamEligible
        processor.update(
            eqEnabled = state.isEnabled && eligible,
            gainsDb = state.activeGainsDb,
            volumeBoost = if (eligible) state.volumeBoostMultiplier else 1f,
        )
    }

    fun refreshStream(context: Context, streamUrl: String?) {
        PlaybackEqualizerStore.getInstance(context).refreshStream(streamUrl)
    }
}
