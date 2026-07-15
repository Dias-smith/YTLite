package com.ytlite.player.ui.subscriptions

import android.app.Application
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.ytlite.player.data.model.ExtractionResult
import com.ytlite.player.data.repository.YoutubeYouRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class YoutubePlaylistItemsViewModel(
    application: Application,
    private val playlistId: String,
    private val title: String,
    private val repository: YoutubeYouRepository = YoutubeYouRepository.getInstance(application),
) : ViewModel() {

    private val _uiState = MutableStateFlow(
        YoutubePlaylistItemsUiState(
            title = title,
            playlistId = playlistId,
            isLoading = true,
        ),
    )
    val uiState: StateFlow<YoutubePlaylistItemsUiState> = _uiState.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _uiState.update {
                it.copy(isLoading = true, errorMessage = null, videos = emptyList(), continuation = null)
            }
            when (val result = repository.fetchPlaylistItems(playlistId)) {
                is ExtractionResult.Success -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            videos = result.data.videos,
                            continuation = result.data.continuation,
                            errorMessage = null,
                        )
                    }
                }
                is ExtractionResult.Error -> {
                    _uiState.update {
                        it.copy(isLoading = false, errorMessage = result.message)
                    }
                }
            }
        }
    }

    fun loadMore() {
        val state = _uiState.value
        val token = state.continuation ?: return
        if (state.isLoadingMore || state.isLoading) return
        viewModelScope.launch {
            _uiState.update { it.copy(isLoadingMore = true) }
            when (val result = repository.fetchPlaylistItems(playlistId, pageToken = token)) {
                is ExtractionResult.Success -> {
                    _uiState.update { current ->
                        current.copy(
                            videos = (current.videos + result.data.videos).distinctBy { it.videoId },
                            continuation = result.data.continuation,
                            isLoadingMore = false,
                        )
                    }
                }
                is ExtractionResult.Error -> {
                    _uiState.update { it.copy(isLoadingMore = false) }
                }
            }
        }
    }

    companion object {
        fun factory(
            application: Application,
            playlistId: String,
            title: String,
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer { YoutubePlaylistItemsViewModel(application, playlistId, title) }
        }
    }
}

class YoutubePlaylistsListViewModel(
    application: Application,
    private val repository: YoutubeYouRepository = YoutubeYouRepository.getInstance(application),
) : ViewModel() {

    private val _uiState = MutableStateFlow(YoutubePlaylistsListUiState(isLoading = true))
    val uiState: StateFlow<YoutubePlaylistsListUiState> = _uiState.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _uiState.update {
                it.copy(isLoading = true, errorMessage = null, playlists = emptyList(), continuation = null)
            }
            when (val result = repository.fetchCustomPlaylists()) {
                is ExtractionResult.Success -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            playlists = result.data.playlists,
                            continuation = result.data.continuation,
                            errorMessage = null,
                        )
                    }
                }
                is ExtractionResult.Error -> {
                    _uiState.update {
                        it.copy(isLoading = false, errorMessage = result.message)
                    }
                }
            }
        }
    }

    fun loadMore() {
        val state = _uiState.value
        val token = state.continuation ?: return
        if (state.isLoadingMore || state.isLoading) return
        viewModelScope.launch {
            _uiState.update { it.copy(isLoadingMore = true) }
            when (val result = repository.fetchCustomPlaylists(pageToken = token)) {
                is ExtractionResult.Success -> {
                    _uiState.update { current ->
                        current.copy(
                            playlists = (current.playlists + result.data.playlists)
                                .distinctBy { it.playlistId },
                            continuation = result.data.continuation,
                            isLoadingMore = false,
                        )
                    }
                }
                is ExtractionResult.Error -> {
                    _uiState.update { it.copy(isLoadingMore = false) }
                }
            }
        }
    }

    companion object {
        fun factory(application: Application): ViewModelProvider.Factory = viewModelFactory {
            initializer { YoutubePlaylistsListViewModel(application) }
        }
    }
}
