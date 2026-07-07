package com.ytlite.player.ui.library

import android.app.Application
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.ytlite.player.data.auth.AuthRepository
import com.ytlite.player.data.auth.UserSession
import com.ytlite.player.data.repository.LibraryRepository
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class LibraryViewModel(
    application: Application,
    private val authRepository: AuthRepository = AuthRepository.getInstance(application),
    private val libraryRepository: LibraryRepository = LibraryRepository.getInstance(application),
) : ViewModel() {

    private val sessionFlow = authRepository.session

    val uiState: StateFlow<LibraryUiState> = sessionFlow
        .flatMapLatest { session ->
            val ownerKey = session?.ownerKey ?: return@flatMapLatest flowOf(LibraryUiState(isLoading = false))
            combine(
                libraryRepository.observeHistory(ownerKey),
                libraryRepository.getUnifiedPlaylists(ownerKey),
            ) { history, playlists ->
                LibraryUiState(
                    session = session,
                    history = history,
                    unifiedPlaylists = playlists,
                    isLoading = false,
                )
            }
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), LibraryUiState())

    fun refreshIfNeeded() {
        viewModelScope.launch {
            val session = authRepository.currentSession()
            if (session is UserSession.Authenticated) {
                libraryRepository.refreshYoutubePlaylists()
            }
        }
    }

    fun cloneYoutubePlaylistToLocal(playlistId: String) {
        viewModelScope.launch {
            val ownerKey = authRepository.currentSession()?.ownerKey ?: return@launch
            libraryRepository.importYoutubePlaylistToLocal(playlistId, ownerKey)
        }
    }

    companion object {
        fun factory(application: Application): ViewModelProvider.Factory = viewModelFactory {
            initializer { LibraryViewModel(application) }
        }
    }
}
