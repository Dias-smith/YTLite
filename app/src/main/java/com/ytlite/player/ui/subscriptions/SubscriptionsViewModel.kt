package com.ytlite.player.ui.subscriptions

import android.app.Application
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.ytlite.player.data.model.ExtractionResult
import com.ytlite.player.data.repository.SubscriptionsRepository
import kotlinx.coroutines.async
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
                _uiState.update { it.copy(youtubeSessionState = sessionState) }
            }
        }
    }

    fun refreshIfNeeded() {
        if (_uiState.value.isLoading) return
        loadFeed()
    }

    fun refresh() {
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

    fun loadMoreChannels() {
        val state = _uiState.value
        val token = state.channelsContinuation ?: return
        if (state.isLoadingMoreChannels || state.isLoading) return

        viewModelScope.launch {
            _uiState.update { it.copy(isLoadingMoreChannels = true) }
            when (val result = repository.fetchChannelsContinuation(token)) {
                is ExtractionResult.Success -> {
                    _uiState.update { current ->
                        val merged = (current.channels + result.data.channels)
                            .distinctBy { it.channelId }
                        current.copy(
                            channels = merged,
                            channelsContinuation = result.data.continuation,
                            isLoadingMoreChannels = false,
                        )
                    }
                }
                is ExtractionResult.Error -> {
                    _uiState.update { it.copy(isLoadingMoreChannels = false) }
                }
            }
        }
    }

    private fun loadFeed() {
        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isLoading = true,
                    errorMessage = null,
                    needsYoutubeReauth = false,
                    videos = emptyList(),
                    channels = emptyList(),
                    continuation = null,
                    channelsContinuation = null,
                )
            }

            val feedDeferred = async { repository.fetchFeed() }
            val channelsDeferred = async { repository.fetchChannels() }
            val feedResult = feedDeferred.await()
            val channelsResult = channelsDeferred.await()

            when (feedResult) {
                is ExtractionResult.Success -> {
                    _uiState.update { current ->
                        current.copy(
                            videos = feedResult.data.videos,
                            continuation = feedResult.data.continuation,
                            isLoading = false,
                            errorMessage = null,
                            needsYoutubeReauth = false,
                        )
                    }
                }
                is ExtractionResult.Error -> {
                    val needsReauth = feedResult.message == SubscriptionsRepository.YOUTUBE_REAUTH_REQUIRED
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            errorMessage = feedResult.message,
                            needsYoutubeReauth = needsReauth,
                        )
                    }
                }
            }

            if (channelsResult is ExtractionResult.Success) {
                _uiState.update { current ->
                    current.copy(
                        channels = channelsResult.data.channels,
                        channelsContinuation = channelsResult.data.continuation,
                    )
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
