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
import com.ytlite.player.data.youtube.YoutubeDiagnostics
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
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

    init {
        viewModelScope.launch {
            authRepository.initialize()
        }
    }

    val uiState: StateFlow<LibraryUiState> = sessionFlow
        .flatMapLatest { session ->
            val ownerKey = session?.ownerKey
                ?: return@flatMapLatest flowOf(LibraryUiState(isLoading = true))
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
            authRepository.initialize()
            val session = authRepository.currentSession()
            if (session == null) {
                YoutubeDiagnostics.logPlaylistsFetchOutcome(
                    step = "Playlists/VM",
                    outcome = "skipped",
                    detail = "session=null after initialize",
                )
                return@launch
            }
            YoutubeDiagnostics.d(
                step = "Playlists/VM",
                message = "refreshIfNeeded ownerKey=${session.ownerKey} type=${session.javaClass.simpleName}",
            )
            libraryRepository.ensureLocalLibraryReady(session.ownerKey)
            if (session is UserSession.Authenticated) {
                libraryRepository.refreshYoutubePlaylists()
                val playlists = libraryRepository.getUnifiedPlaylists(session.ownerKey).first()
                val youtube = playlists.filter { it.isYoutube() }
                val local = playlists.filter { it.isLocal() }
                YoutubeDiagnostics.logUnifiedPlaylistsSnapshot(
                    step = "Playlists/VM",
                    ownerKey = session.ownerKey,
                    localCount = local.size,
                    youtubeCount = youtube.size,
                    youtubeIds = youtube.map { "${it.name}:${it.playlistId}" },
                )
            } else {
                YoutubeDiagnostics.logPlaylistsFetchOutcome(
                    step = "Playlists/VM",
                    outcome = "skipped",
                    detail = "not Authenticated session=${session.javaClass.simpleName}",
                )
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
