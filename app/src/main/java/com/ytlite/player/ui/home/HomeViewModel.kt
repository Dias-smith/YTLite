package com.ytlite.player.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ytlite.player.data.model.ExtractionResult
import com.ytlite.player.data.repository.ExtractionRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class HomeViewModel(
    private val repository: ExtractionRepository = ExtractionRepository.getInstance(),
) : ViewModel() {

    private val _uiState = MutableStateFlow(HomeUiState())
    val uiState: StateFlow<HomeUiState> = _uiState.asStateFlow()

    init {
        loadFeed()
    }

    fun loadFeed() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, errorMessage = null) }
            when (val result = repository.fetchHomeFeed()) {
                is ExtractionResult.Success -> {
                    _uiState.update {
                        it.copy(
                            videos = result.data.videos,
                            continuation = result.data.continuation,
                            isLoading = false,
                            errorMessage = null,
                        )
                    }
                }
                is ExtractionResult.Error -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            errorMessage = result.message,
                        )
                    }
                }
            }
        }
    }

    fun refresh() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, errorMessage = null) }
            when (val result = repository.fetchHomeFeed()) {
                is ExtractionResult.Success -> {
                    _uiState.update {
                        it.copy(
                            videos = result.data.videos,
                            continuation = result.data.continuation,
                            isLoading = false,
                            errorMessage = null,
                        )
                    }
                }
                is ExtractionResult.Error -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            errorMessage = result.message,
                        )
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
            when (val result = repository.fetchHomeFeedContinuation(token)) {
                is ExtractionResult.Success -> {
                    _uiState.update { current ->
                        val merged = (current.videos + result.data.videos)
                            .distinctBy { it.videoId }
                        current.copy(
                            videos = merged,
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
}
