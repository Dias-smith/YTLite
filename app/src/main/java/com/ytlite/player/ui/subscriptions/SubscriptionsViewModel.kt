package com.ytlite.player.ui.subscriptions

import android.app.Application
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.ytlite.player.data.model.ExtractionResult
import com.ytlite.player.data.repository.SubscriptionsRepository
import com.ytlite.player.data.youtube.YoutubeDiagnostics
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class SubscriptionsViewModel(
    application: Application,
    private val repository: SubscriptionsRepository = SubscriptionsRepository.getInstance(application),
) : ViewModel() {

    private val _uiState = MutableStateFlow(SubscriptionsUiState())
    val uiState: StateFlow<SubscriptionsUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            repository.youtubeSessionState.collect { sessionState ->
                YoutubeDiagnostics.d("ViewModel", "youtubeSessionState=$sessionState")
                _uiState.update { it.copy(youtubeSessionState = sessionState) }
            }
        }
    }

    fun refreshIfNeeded() {
        YoutubeDiagnostics.d("ViewModel", "refreshIfNeeded isLoading=${_uiState.value.isLoading}")
        if (_uiState.value.isLoading) return
        loadFeed()
    }

    fun refresh() {
        YoutubeDiagnostics.d("ViewModel", "refresh (retry)")
        loadFeed()
    }

    fun loadMore() {
        val state = _uiState.value
        val token = state.continuation ?: return
        if (state.isLoadingMore || state.isLoading) return

        viewModelScope.launch {
            _uiState.update { it.copy(isLoadingMore = true) }
            when (val result = repository.fetchFeedContinuation(token)) {
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

    fun openChannelList() {
        _uiState.update { it.copy(showChannelList = true) }
    }

    fun closeChannelList() {
        _uiState.update { it.copy(showChannelList = false) }
    }

    private fun loadFeed() {
        viewModelScope.launch {
            YoutubeDiagnostics.d("ViewModel", "loadFeed start")
            _uiState.update {
                it.copy(
                    isLoading = true,
                    errorMessage = null,
                    needsYoutubeReauth = false,
                    videos = emptyList(),
                    continuation = null,
                )
            }
            when (val result = repository.fetchFeed()) {
                is ExtractionResult.Success -> {
                    YoutubeDiagnostics.d(
                        "ViewModel",
                        "loadFeed success videos=${result.data.videos.size} " +
                            "continuation=${result.data.continuation != null}",
                    )
                    _uiState.update {
                        it.copy(
                            videos = result.data.videos,
                            continuation = result.data.continuation,
                            isLoading = false,
                            errorMessage = null,
                            needsYoutubeReauth = false,
                        )
                    }
                }
                is ExtractionResult.Error -> {
                    YoutubeDiagnostics.e("ViewModel", "loadFeed error: ${result.message}", result.cause)
                    val needsReauth = result.message == SubscriptionsRepository.YOUTUBE_REAUTH_REQUIRED
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            errorMessage = result.message,
                            needsYoutubeReauth = needsReauth,
                        )
                    }
                }
            }
        }
    }

    companion object {
        fun factory(application: Application): ViewModelProvider.Factory = viewModelFactory {
            initializer { SubscriptionsViewModel(application) }
        }
    }
}
