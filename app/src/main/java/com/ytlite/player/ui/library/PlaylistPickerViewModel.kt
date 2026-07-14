package com.ytlite.player.ui.library

import android.app.Application
import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.ytlite.player.data.auth.AuthRepository
import com.ytlite.player.data.auth.UserSession
import com.ytlite.player.data.local.entity.PlaylistSystemType
import com.ytlite.player.data.model.LibraryFilterChip
import com.ytlite.player.data.model.LibraryItem
import com.ytlite.player.data.model.LibrarySort
import com.ytlite.player.data.model.LibraryVideo
import com.ytlite.player.data.repository.LibraryRepository
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

@Immutable
data class PlaylistPickerOption(
    val playlistId: String,
    val systemType: String? = null,
    val name: String = "",
)

@Immutable
data class PlaylistPickerUiState(
    val playlists: List<PlaylistPickerOption> = emptyList(),
)

class PlaylistPickerViewModel(
    private val libraryRepository: LibraryRepository,
    private val authRepository: AuthRepository,
) : ViewModel() {

    val uiState: StateFlow<PlaylistPickerUiState> = authRepository.session
        .flatMapLatest { session ->
            val ownerKey = session?.ownerKey
                ?: return@flatMapLatest flowOf(PlaylistPickerUiState())
            val isAuthenticated = session is UserSession.Authenticated
            libraryRepository.observeLibraryItems(
                ownerKey = ownerKey,
                filter = LibraryFilterChip.PLAYLISTS,
                sort = LibrarySort.RECENT_ACTIVITY,
                isAuthenticated = isAuthenticated,
            ).map { items ->
                PlaylistPickerUiState(
                    playlists = items
                        .filterIsInstance<LibraryItem.Playlist>()
                        .filter { it.systemType != PlaylistSystemType.HISTORY }
                        .map {
                            PlaylistPickerOption(
                                playlistId = it.playlistId,
                                systemType = it.systemType,
                                name = it.title,
                            )
                        },
                )
            }
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), PlaylistPickerUiState())

    fun saveToPlaylist(playlistId: String, video: LibraryVideo, onDone: () -> Unit) {
        viewModelScope.launch {
            libraryRepository.addTrackToPlaylist(playlistId, video)
            onDone()
        }
    }

    fun createAndSave(name: String, video: LibraryVideo, onDone: () -> Unit) {
        viewModelScope.launch {
            val ownerKey = authRepository.currentSession()?.ownerKey ?: return@launch
            val playlistId = libraryRepository.createLocalPlaylist(ownerKey, name)
            libraryRepository.addTrackToPlaylist(playlistId, video)
            onDone()
        }
    }

    companion object {
        fun factory(application: Application): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                PlaylistPickerViewModel(
                    libraryRepository = LibraryRepository.getInstance(application),
                    authRepository = AuthRepository.getInstance(application),
                )
            }
        }
    }
}
