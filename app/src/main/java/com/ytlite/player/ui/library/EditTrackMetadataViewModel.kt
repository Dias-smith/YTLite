package com.ytlite.player.ui.library

import android.app.Application
import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.ytlite.player.data.auth.AuthRepository
import com.ytlite.player.data.model.ResolvedTrackMetadata
import com.ytlite.player.data.model.TrackMetadataEdits
import com.ytlite.player.data.repository.LibraryRepository
import com.ytlite.player.playback.NowPlaying
import com.ytlite.player.playback.PlayQueueRepository
import com.ytlite.player.playback.PlaybackManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

@Immutable
data class EditTrackMetadataUiState(
    val trackId: String = "",
    val title: String = "",
    val artistName: String = "",
    val album: String = "",
    val year: String = "",
    val thumbnailUrl: String = "",
    val hasOverride: Boolean = false,
    val isLoading: Boolean = true,
    val isSaving: Boolean = false,
    val errorMessage: String? = null,
    val savedMetadata: ResolvedTrackMetadata? = null,
)

class EditTrackMetadataViewModel(
    private val trackId: String,
    private val authRepository: AuthRepository,
    private val libraryRepository: LibraryRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(EditTrackMetadataUiState(trackId = trackId))
    val uiState: StateFlow<EditTrackMetadataUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            val ownerKey = authRepository.currentSession()?.ownerKey
            if (ownerKey == null) {
                _uiState.update { it.copy(isLoading = false, errorMessage = "not_signed_in") }
                return@launch
            }
            val resolved = libraryRepository.getResolvedMetadata(ownerKey, trackId)
            if (resolved == null) {
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        title = "",
                        artistName = "",
                        thumbnailUrl = "",
                    )
                }
            } else {
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        title = resolved.title,
                        artistName = resolved.artistName,
                        album = resolved.album.orEmpty(),
                        year = resolved.year.orEmpty(),
                        thumbnailUrl = resolved.thumbnailUrl,
                        hasOverride = resolved.hasUserOverride,
                    )
                }
            }
        }
    }

    fun updateTitle(value: String) = _uiState.update { it.copy(title = value) }
    fun updateArtistName(value: String) = _uiState.update { it.copy(artistName = value) }
    fun updateAlbum(value: String) = _uiState.update { it.copy(album = value) }
    fun updateYear(value: String) = _uiState.update { it.copy(year = value) }
    fun updateThumbnailUrl(value: String) = _uiState.update { it.copy(thumbnailUrl = value) }

    fun save() {
        viewModelScope.launch {
            val ownerKey = authRepository.currentSession()?.ownerKey ?: return@launch
            val state = _uiState.value
            _uiState.update { it.copy(isSaving = true, errorMessage = null) }
            val edits = TrackMetadataEdits.fromForm(
                title = state.title,
                artistName = state.artistName,
                thumbnailUrl = state.thumbnailUrl,
                album = state.album,
                year = state.year,
            )
            val resolved = libraryRepository.upsertTrackMetadata(ownerKey, trackId, edits)
            if (resolved != null) {
                applyResolvedMetadata(resolved)
            }
            _uiState.update {
                it.copy(
                    isSaving = false,
                    hasOverride = resolved?.hasUserOverride == true,
                    savedMetadata = resolved,
                )
            }
        }
    }

    fun resetToDefault() {
        viewModelScope.launch {
            val ownerKey = authRepository.currentSession()?.ownerKey ?: return@launch
            _uiState.update { it.copy(isSaving = true, errorMessage = null) }
            libraryRepository.resetTrackMetadata(ownerKey, trackId)
            val resolved = libraryRepository.getResolvedMetadata(ownerKey, trackId)
            if (resolved != null) {
                applyResolvedMetadata(resolved)
                _uiState.update {
                    it.copy(
                        isSaving = false,
                        hasOverride = false,
                        title = resolved.title,
                        artistName = resolved.artistName,
                        album = resolved.album.orEmpty(),
                        year = resolved.year.orEmpty(),
                        thumbnailUrl = resolved.thumbnailUrl,
                        savedMetadata = resolved,
                    )
                }
            } else {
                _uiState.update { it.copy(isSaving = false, hasOverride = false, savedMetadata = null) }
            }
        }
    }

    private fun applyResolvedMetadata(resolved: ResolvedTrackMetadata) {
        PlayQueueRepository.updateItemMetadata(
            videoId = resolved.trackId,
            title = resolved.title,
            channelName = resolved.artistName,
            thumbnailUrl = resolved.thumbnailUrl,
            album = resolved.album,
            year = resolved.year,
        )
        val nowPlaying = PlaybackManager.nowPlaying.value
        if (nowPlaying?.videoId == resolved.trackId) {
            PlaybackManager.updateNowPlayingMetadata(
                title = resolved.title,
                channelName = resolved.artistName,
                thumbnailUrl = resolved.thumbnailUrl,
            )
        }
    }

    companion object {
        fun factory(application: Application, trackId: String): ViewModelProvider.Factory =
            viewModelFactory {
                initializer {
                    EditTrackMetadataViewModel(
                        trackId = trackId,
                        authRepository = AuthRepository.getInstance(application),
                        libraryRepository = LibraryRepository.getInstance(application),
                    )
                }
            }
    }
}
