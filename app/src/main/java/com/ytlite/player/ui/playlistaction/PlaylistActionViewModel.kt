package com.ytlite.player.ui.playlistaction

import android.app.Application
import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.ytlite.player.data.local.entity.PlaylistSystemType
import com.ytlite.player.data.repository.LibraryRepository
import com.ytlite.player.playback.QueueItem
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

@Immutable
data class PlaylistActionUiState(
    val trackCount: Int = 0,
    val totalDurationSeconds: Int = 0,
    val isPinned: Boolean = false,
    val isLoading: Boolean = true,
)

class PlaylistActionViewModel(
    private val context: PlaylistActionContext,
    private val libraryRepository: LibraryRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(PlaylistActionUiState(isPinned = context.isPinned))
    val uiState: StateFlow<PlaylistActionUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            if (!context.isHistoryVirtual) {
                launch {
                    libraryRepository.observePlaylistPin(context.playlistId, context.ownerKey)
                        .collect { isPinned ->
                            _uiState.update { it.copy(isPinned = isPinned) }
                        }
                }
            }
            if (context.isHistoryVirtual) {
                val history = libraryRepository.observeAllHistory(context.ownerKey).first()
                _uiState.update {
                    it.copy(
                        trackCount = history.size,
                        totalDurationSeconds = 0,
                        isLoading = false,
                    )
                }
                return@launch
            }
            val resolvedId = resolveStatsPlaylistId()
            if (resolvedId == null) {
                _uiState.update { it.copy(isLoading = false) }
                return@launch
            }
            libraryRepository.observePlaylistStats(resolvedId).collect { stats ->
                _uiState.update {
                    it.copy(
                        trackCount = stats.trackCount,
                        totalDurationSeconds = stats.totalDurationSeconds,
                        isLoading = false,
                    )
                }
            }
        }
    }

    suspend fun loadQueueItems(): List<QueueItem> =
        libraryRepository.getPlaylistQueueItems(
            ownerKey = context.ownerKey,
            playlistId = context.playlistId,
            systemType = context.systemType,
        )

    fun renamePlaylist(name: String, onDone: (Boolean) -> Unit) {
        viewModelScope.launch {
            val success = libraryRepository.renameLocalPlaylist(
                playlistId = context.playlistId,
                ownerKey = context.ownerKey,
                name = name,
            )
            onDone(success)
        }
    }

    fun togglePin(onDone: (Boolean) -> Unit) {
        viewModelScope.launch {
            val success = libraryRepository.togglePlaylistPin(
                playlistId = context.playlistId,
                ownerKey = context.ownerKey,
            )
            onDone(success)
        }
    }

    fun deletePlaylist(onDone: (Boolean) -> Unit) {
        viewModelScope.launch {
            val success = libraryRepository.deleteLocalPlaylist(
                playlistId = context.playlistId,
                ownerKey = context.ownerKey,
            )
            onDone(success)
        }
    }

    private suspend fun resolveStatsPlaylistId(): String? {
        if (context.systemType != null && context.systemType != PlaylistSystemType.HISTORY) {
            return libraryRepository.getPlaylistById(
                playlistId = context.playlistId,
                ownerKey = context.ownerKey,
                systemType = context.systemType,
            )?.playlistId ?: context.playlistId.takeIf { !it.startsWith("system:") }
        }
        return context.playlistId.takeIf { !it.startsWith("system:") }
    }

    companion object {
        fun factory(
            application: Application,
            context: PlaylistActionContext,
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                PlaylistActionViewModel(
                    context = context,
                    libraryRepository = LibraryRepository.getInstance(application),
                )
            }
        }
    }
}
