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

@Immutable
data class AlbumTracksUiState(
    val tracks: List<LibraryVideo> = emptyList(),
)

class AlbumTracksViewModel(
    ownerKey: String,
    albumName: String,
    libraryRepository: LibraryRepository,
) : ViewModel() {

    val uiState: StateFlow<AlbumTracksUiState> = libraryRepository
        .observeAlbumTracks(ownerKey, albumName)
        .map { AlbumTracksUiState(tracks = it) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), AlbumTracksUiState())

    companion object {
        fun factory(
            application: Application,
            ownerKey: String,
            albumName: String,
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                AlbumTracksViewModel(
                    ownerKey = ownerKey,
                    albumName = albumName,
                    libraryRepository = LibraryRepository.getInstance(application),
                )
            }
        }
    }
}
