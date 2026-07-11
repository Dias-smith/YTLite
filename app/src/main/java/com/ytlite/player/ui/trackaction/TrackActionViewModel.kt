package com.ytlite.player.ui.trackaction

import android.app.Application
import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.ytlite.player.data.auth.AuthRepository
import com.ytlite.player.data.model.DataSource
import com.ytlite.player.data.repository.LibraryRepository
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

@Immutable
data class TrackActionUiState(
    val isLiked: Boolean = false,
    val isNotInterested: Boolean = false,
    val canGoToAlbum: Boolean = false,
    val canGoToArtist: Boolean = false,
    val canRemoveFromPlaylist: Boolean = false,
)

class TrackActionViewModel(
    private val context: TrackActionContext,
    private val authRepository: AuthRepository,
    private val libraryRepository: LibraryRepository,
) : ViewModel() {

    val uiState: StateFlow<TrackActionUiState> = authRepository.session
        .flatMapLatest { session ->
            val ownerKey = session?.ownerKey
                ?: return@flatMapLatest flowOf(
                    TrackActionUiState(
                        canGoToAlbum = !context.album.isNullOrBlank(),
                        canGoToArtist = !context.channelId.isNullOrBlank(),
                        canRemoveFromPlaylist = context.playlistSource == DataSource.LOCAL &&
                            context.playlistId != null,
                    ),
                )
            combine(
                libraryRepository.observeIsTrackLiked(ownerKey, context.videoId),
                libraryRepository.observeIsNotInterested(ownerKey, context.videoId),
            ) { liked, notInterested ->
                TrackActionUiState(
                    isLiked = liked,
                    isNotInterested = notInterested,
                    canGoToAlbum = !context.album.isNullOrBlank(),
                    canGoToArtist = !context.channelId.isNullOrBlank(),
                    canRemoveFromPlaylist = context.playlistSource == DataSource.LOCAL &&
                        context.playlistId != null,
                )
            }
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), TrackActionUiState())

    fun toggleFavorite() {
        viewModelScope.launch {
            val ownerKey = authRepository.currentSession()?.ownerKey ?: return@launch
            val video = context.toLibraryVideo()
            if (uiState.value.isLiked) {
                libraryRepository.removeTrackFromFavorites(ownerKey, context.videoId)
            } else {
                libraryRepository.addTrackToFavorites(ownerKey, video)
                if (uiState.value.isNotInterested) {
                    libraryRepository.removeNotInterested(ownerKey, context.videoId)
                }
            }
        }
    }

    fun toggleNotInterested() {
        viewModelScope.launch {
            val ownerKey = authRepository.currentSession()?.ownerKey ?: return@launch
            if (uiState.value.isNotInterested) {
                libraryRepository.removeNotInterested(ownerKey, context.videoId)
            } else {
                libraryRepository.addNotInterested(ownerKey, context.videoId)
                if (uiState.value.isLiked) {
                    libraryRepository.removeTrackFromFavorites(ownerKey, context.videoId)
                }
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
            context: TrackActionContext,
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                TrackActionViewModel(
                    context = context,
                    authRepository = AuthRepository.getInstance(application),
                    libraryRepository = LibraryRepository.getInstance(application),
                )
            }
        }
    }
}
