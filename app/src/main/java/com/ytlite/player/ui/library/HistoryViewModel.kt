package com.ytlite.player.ui.library

import android.app.Application
import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.ytlite.player.data.model.LibraryVideo
import com.ytlite.player.data.repository.LibraryRepository
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import java.time.Instant
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.TextStyle
import java.util.Locale

@Immutable
data class HistoryUiState(
    val groupedHistory: Map<String, List<LibraryVideo>> = emptyMap(),
    val isLoading: Boolean = true,
)

class HistoryViewModel(
    private val ownerKey: String,
    private val libraryRepository: LibraryRepository,
) : ViewModel() {

    private val zoneId = ZoneId.systemDefault()

    val uiState: StateFlow<HistoryUiState> = libraryRepository
        .observeAllHistory(ownerKey)
        .map { videos ->
            HistoryUiState(
                groupedHistory = groupByMonth(videos),
                isLoading = false,
            )
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), HistoryUiState())

    private fun groupByMonth(videos: List<LibraryVideo>): Map<String, List<LibraryVideo>> =
        videos
            .groupBy { video ->
                val month = YearMonth.from(Instant.ofEpochMilli(video.watchedAt).atZone(zoneId))
                monthLabel(month)
            }
            .toSortedMap(compareByDescending { key ->
                videos.firstOrNull { monthLabel(YearMonth.from(Instant.ofEpochMilli(it.watchedAt).atZone(zoneId))) == key }
                    ?.watchedAt ?: 0L
            })

    private fun monthLabel(month: YearMonth): String {
        val monthName = month.month.getDisplayName(TextStyle.FULL, Locale.getDefault())
        return "$monthName ${month.year}"
    }

    companion object {
        fun factory(
            application: Application,
            ownerKey: String,
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                HistoryViewModel(
                    ownerKey = ownerKey,
                    libraryRepository = LibraryRepository.getInstance(application),
                )
            }
        }
    }
}
