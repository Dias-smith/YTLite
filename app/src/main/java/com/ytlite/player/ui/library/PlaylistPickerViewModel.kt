package com.ytlite.player.ui.library

import android.app.Application
import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.ytlite.player.data.auth.AuthRepository
import com.ytlite.player.data.local.entity.PlaylistEntity
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
data class PlaylistPickerUiState(
    val playlists: List<PlaylistEntity> = emptyList(),
)

class PlaylistPickerViewModel(
    private val libraryRepository: LibraryRepository,
    private val authRepository: AuthRepository,
) : ViewModel() {

    val uiState: StateFlow<PlaylistPickerUiState> = authRepository.session
        .flatMapLatest { session ->
            val ownerKey = session?.ownerKey
                ?: return@flatMapLatest flowOf(PlaylistPickerUiState())
            libraryRepository.getUnifiedPlaylists(ownerKey).map { playlists ->
                PlaylistPickerUiState(
                    playlists = playlists.filter { it.systemType == null },
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
