package com.ytlite.player.playback

import android.content.Context
import com.ytlite.player.R
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
data class PlaybackEqualizerPreset(
    val id: String,
    val nameKey: String,
    val gainsDb: List<Float>,
)

object PlaybackEqualizerCatalog {
    const val CUSTOM_PRESET_ID = "custom"
    const val BAND_COUNT = 10
    const val MIN_GAIN_DB = -12f
    const val MAX_GAIN_DB = 12f
    const val MIN_VOLUME_BOOST_PERCENT = 100f
    const val MAX_VOLUME_BOOST_PERCENT = 500f
    const val DEFAULT_VOLUME_BOOST_PERCENT = 100f

    fun volumeBoostMultiplier(percent: Float): Float =
        percent.coerceIn(MIN_VOLUME_BOOST_PERCENT, MAX_VOLUME_BOOST_PERCENT) / 100f

    private val json = Json { ignoreUnknownKeys = true }

    private var loaded = false
    private var bandFrequenciesHz: IntArray = intArrayOf(
        32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000,
    )
    private var presets: List<PlaybackEqualizerPreset> = emptyList()

    fun ensureLoaded(context: Context) {
        if (loaded) return
        synchronized(this) {
            if (loaded) return
            val catalog = runCatching {
                context.assets.open("playback_equalizer_presets.json")
                    .bufferedReader()
                    .use { reader ->
                        json.decodeFromString<CatalogDto>(reader.readText())
                    }
            }.getOrNull()
            if (catalog != null && catalog.presets.all { it.gainsDb.size == BAND_COUNT }) {
                bandFrequenciesHz = catalog.bandFrequenciesHz.toIntArray()
                presets = catalog.presets.map {
                    PlaybackEqualizerPreset(
                        id = it.id,
                        nameKey = it.nameKey,
                        gainsDb = it.gainsDb.map(Double::toFloat),
                    )
                } + customPreset()
            } else {
                presets = listOf(
                    PlaybackEqualizerPreset(
                        id = "flat",
                        nameKey = "equalizer.preset.flat",
                        gainsDb = flatGains().toList(),
                    ),
                ) + customPreset()
            }
            loaded = true
        }
    }

    fun bandFrequencies(context: Context): IntArray {
        ensureLoaded(context)
        return bandFrequenciesHz
    }

    fun presets(context: Context): List<PlaybackEqualizerPreset> {
        ensureLoaded(context)
        return presets
    }

    fun isCustomPreset(id: String): Boolean = id == CUSTOM_PRESET_ID

    fun preset(id: String): PlaybackEqualizerPreset? {
        check(loaded) { "Call ensureLoaded(context) before reading presets." }
        if (isCustomPreset(id)) return customPreset()
        return presets.firstOrNull { it.id == id && !isCustomPreset(it.id) }
    }

    fun preset(context: Context, id: String): PlaybackEqualizerPreset? {
        ensureLoaded(context)
        return preset(id)
    }

    fun flatGains(): FloatArray = FloatArray(BAND_COUNT)

    fun presetLabelRes(preset: PlaybackEqualizerPreset): Int = when (preset.nameKey) {
        "equalizer.preset.flat" -> R.string.equalizer_preset_flat
        "equalizer.preset.bass_boost" -> R.string.equalizer_preset_bass_boost
        "equalizer.preset.treble_boost" -> R.string.equalizer_preset_treble_boost
        "equalizer.preset.vocal" -> R.string.equalizer_preset_vocal
        "equalizer.preset.rock" -> R.string.equalizer_preset_rock
        "equalizer.preset.pop" -> R.string.equalizer_preset_pop
        "equalizer.preset.electronic" -> R.string.equalizer_preset_electronic
        "equalizer.preset.classical" -> R.string.equalizer_preset_classical
        "equalizer.preset.custom" -> R.string.equalizer_preset_custom
        else -> R.string.equalizer_preset_flat
    }

    private fun customPreset(): PlaybackEqualizerPreset = PlaybackEqualizerPreset(
        id = CUSTOM_PRESET_ID,
        nameKey = "equalizer.preset.custom",
        gainsDb = flatGains().toList(),
    )

    @Serializable
    private data class CatalogDto(
        val bandFrequenciesHz: List<Int>,
        val presets: List<PresetDto>,
    )

    @Serializable
    private data class PresetDto(
        val id: String,
        val nameKey: String,
        val gainsDb: List<Double>,
    )
}
