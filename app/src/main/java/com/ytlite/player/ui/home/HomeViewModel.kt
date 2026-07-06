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
        val category = HomeCategories.find(_uiState.value.selectedCategoryId)
            ?: HomeCategories.items.first()
        loadFeedForCategory(category)
    }

    fun refresh() {
        val category = HomeCategories.find(_uiState.value.selectedCategoryId)
            ?: HomeCategories.items.first()
        loadFeedForCategory(category)
    }

    fun selectCategory(categoryId: String) {
        if (categoryId == _uiState.value.selectedCategoryId) return
        val category = HomeCategories.find(categoryId) ?: return
        _uiState.update { it.copy(selectedCategoryId = categoryId) }
        loadFeedForCategory(category)
    }

    fun loadMore() {
        val state = _uiState.value
        val token = state.continuation ?: return
        if (state.isLoadingMore || state.isLoading) return

        viewModelScope.launch {
            _uiState.update { it.copy(isLoadingMore = true) }
            when (
                val result = repository.fetchHomeFeedContinuation(
                    continuation = token,
                    searchQuery = state.feedSearchQuery,
                )
            ) {
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

    private fun loadFeedForCategory(category: FeedCategory) {
        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isLoading = true,
                    errorMessage = null,
                    videos = emptyList(),
                    continuation = null,
                )
            }
            when (val result = repository.fetchHomeFeed(searchQuery = category.searchQuery)) {
                is ExtractionResult.Success -> {
                    _uiState.update {
                        it.copy(
                            videos = result.data.videos,
                            continuation = result.data.continuation,
                            feedSearchQuery = category.searchQuery,
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
}
