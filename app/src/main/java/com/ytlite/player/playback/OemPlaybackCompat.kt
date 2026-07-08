package com.ytlite.player.playback

import android.app.NotificationManager
import android.os.Build
import android.util.Log

/**
 * OEM-specific playback notification and foreground service tweaks.
 *
 * Chinese ROMs (MIUI/HyperOS, EMUI/HarmonyOS, ColorOS, OriginOS) often suppress
 * low-importance media notifications on the lock screen and in the shade.
 */
object OemPlaybackCompat {

    private const val TAG = "OemPlaybackCompat"

    enum class Profile {
        STOCK,
        XIAOMI,
        HUAWEI,
        OPPO,
        VIVO,
        SAMSUNG,
        OTHER,
    }

    val profile: Profile by lazy { detectProfile() }

    fun notificationImportance(): Int = when (profile) {
        Profile.STOCK -> NotificationManager.IMPORTANCE_LOW
        Profile.SAMSUNG -> NotificationManager.IMPORTANCE_LOW
        Profile.XIAOMI,
        Profile.HUAWEI,
        Profile.OPPO,
        Profile.VIVO,
        Profile.OTHER,
        -> NotificationManager.IMPORTANCE_DEFAULT
    }

    /** Aggressive foreground keeps the service alive on battery-restrictive ROMs. */
    fun prefersPersistentForeground(): Boolean = when (profile) {
        Profile.XIAOMI,
        Profile.HUAWEI,
        Profile.OPPO,
        Profile.VIVO,
        -> true
        else -> false
    }

    fun logProfile() {
        Log.i(
            TAG,
            "manufacturer=${Build.MANUFACTURER} brand=${Build.BRAND} " +
                "profile=$profile importance=${notificationImportance()}",
        )
    }

    private fun detectProfile(): Profile {
        val manufacturer = Build.MANUFACTURER.orEmpty().lowercase()
        val brand = Build.BRAND.orEmpty().lowercase()
        return when {
            manufacturer in XIAOMI_MANUFACTURERS || brand in XIAOMI_MANUFACTURERS -> Profile.XIAOMI
            manufacturer in HUAWEI_MANUFACTURERS || brand in HUAWEI_MANUFACTURERS -> Profile.HUAWEI
            manufacturer in OPPO_MANUFACTURERS || brand in OPPO_MANUFACTURERS -> Profile.OPPO
            manufacturer in VIVO_MANUFACTURERS || brand in VIVO_MANUFACTURERS -> Profile.VIVO
            manufacturer == "google" || brand == "google" -> Profile.STOCK
            manufacturer == "samsung" || brand == "samsung" -> Profile.SAMSUNG
            else -> Profile.OTHER
        }
    }

    private val XIAOMI_MANUFACTURERS = setOf("xiaomi", "redmi", "poco", "blackshark")
    private val HUAWEI_MANUFACTURERS = setOf("huawei", "honor")
    private val OPPO_MANUFACTURERS = setOf("oppo", "realme", "oneplus")
    private val VIVO_MANUFACTURERS = setOf("vivo", "iqoo")
}
