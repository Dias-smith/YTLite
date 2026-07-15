package com.ytlite.player.ui.settings

import android.app.Application
import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.ytlite.player.data.preferences.AppPreferences
import com.ytlite.player.data.preferences.DefaultDownloadFormat
import com.ytlite.player.data.preferences.DownloadPreferences
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

@Immutable
data class SettingsUiState(
    val nightModeEnabled: Boolean = AppPreferences.DEFAULT_NIGHT_MODE,
    val appLanguage: String = AppPreferences.LANGUAGE_SYSTEM,
    val downloadThreadCount: Int = DownloadPreferences.DEFAULT_THREAD_COUNT,
    val downloadResumeEnabled: Boolean = true,
    val downloadWifiOnly: Boolean = false,
    val defaultDownloadFormat: DefaultDownloadFormat = DefaultDownloadFormat.AskEachTime,
)

class SettingsViewModel(
    private val appPreferences: AppPreferences,
    private val downloadPreferences: DownloadPreferences,
) : ViewModel() {

    val uiState: StateFlow<SettingsUiState> = combine(
        combine(
            appPreferences.nightModeEnabled,
            appPreferences.appLanguage,
        ) { nightMode, language -> nightMode to language },
        combine(
            downloadPreferences.threadCount,
            downloadPreferences.resumeEnabled,
            downloadPreferences.wifiOnly,
            downloadPreferences.defaultFormat,
        ) { threadCount, resume, wifiOnly, format ->
            DownloadSettingsSlice(threadCount, resume, wifiOnly, format)
        },
    ) { appearance, download ->
        SettingsUiState(
            nightModeEnabled = appearance.first,
            appLanguage = appearance.second,
            downloadThreadCount = download.threadCount,
            downloadResumeEnabled = download.resumeEnabled,
            downloadWifiOnly = download.wifiOnly,
            defaultDownloadFormat = download.defaultFormat,
        )
    }.stateIn(
        viewModelScope,
        SharingStarted.WhileSubscribed(5_000),
        SettingsUiState(),
    )

    fun setNightModeEnabled(enabled: Boolean) {
        viewModelScope.launch {
            appPreferences.setNightModeEnabled(enabled)
        }
    }

    fun setAppLanguage(language: String, onDone: () -> Unit) {
        viewModelScope.launch {
            appPreferences.setAppLanguage(language)
            onDone()
        }
    }

    fun setDownloadThreadCount(count: Int) {
        viewModelScope.launch { downloadPreferences.setThreadCount(count) }
    }

    fun setDownloadResumeEnabled(enabled: Boolean) {
        viewModelScope.launch { downloadPreferences.setResumeEnabled(enabled) }
    }

    fun setDownloadWifiOnly(enabled: Boolean) {
        viewModelScope.launch { downloadPreferences.setWifiOnly(enabled) }
    }

    fun setDefaultDownloadFormat(format: DefaultDownloadFormat) {
        viewModelScope.launch { downloadPreferences.setDefaultFormat(format) }
    }

    companion object {
        fun factory(application: Application): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                SettingsViewModel(
                    AppPreferences.getInstance(application),
                    DownloadPreferences.getInstance(application),
                )
            }
        }
    }
}

@Immutable
private data class DownloadSettingsSlice(
    val threadCount: Int,
    val resumeEnabled: Boolean,
    val wifiOnly: Boolean,
    val defaultFormat: DefaultDownloadFormat,
)
