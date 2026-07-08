package com.ytlite.player.ui.library

import android.app.Application
import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.ytlite.player.data.auth.AuthRepository
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
data class SongActionUiState(
    val isLiked: Boolean = false,
)

class SongActionViewModel(
    private val context: SongActionContext,
    private val authRepository: AuthRepository,
    private val libraryRepository: LibraryRepository,
) : ViewModel() {

    val uiState: StateFlow<SongActionUiState> = authRepository.session
        .flatMapLatest { session ->
            val ownerKey = session?.ownerKey
                ?: return@flatMapLatest flowOf(SongActionUiState())
            libraryRepository.observeIsTrackLiked(ownerKey, context.videoId)
                .map { SongActionUiState(isLiked = it) }
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), SongActionUiState())

    fun toggleFavorite() {
        viewModelScope.launch {
            val ownerKey = authRepository.currentSession()?.ownerKey ?: return@launch
            val video = LibraryVideo(
                videoId = context.videoId,
                title = context.title,
                channelName = context.channelName,
                thumbnailUrl = context.thumbnailUrl,
            )
            if (uiState.value.isLiked) {
                libraryRepository.removeTrackFromFavorites(ownerKey, context.videoId)
            } else {
                libraryRepository.addTrackToFavorites(ownerKey, video)
            }
        }
    }

    fun removeFromPlaylist() {
        viewModelScope.launch {
            val playlistId = context.playlistId ?: return@launch
            libraryRepository.removeTrackFromPlaylist(playlistId, context.videoId)
        }
    }

    companion object {
        fun factory(
            application: Application,
            context: SongActionContext,
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                SongActionViewModel(
                    context = context,
                    authRepository = AuthRepository.getInstance(application),
                    libraryRepository = LibraryRepository.getInstance(application),
                )
            }
        }
    }
}
