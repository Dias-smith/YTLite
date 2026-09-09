package com.ytlite.player.ui.subscriptions

import android.app.Application
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.ytlite.player.data.model.ExtractionResult
import com.ytlite.player.data.model.SubscriptionChannel
import com.ytlite.player.data.auth.AuthRepository
import com.ytlite.player.data.repository.LibraryRepository
import com.ytlite.player.data.repository.SubscriptionsRepository
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

@OptIn(ExperimentalCoroutinesApi::class)
class ChannelVideosViewModel(
    application: Application,
    private val channel: SubscriptionChannel,
    private val repository: SubscriptionsRepository = SubscriptionsRepository.getInstance(application),
    private val libraryRepository: LibraryRepository = LibraryRepository.getInstance(application),
    private val authRepository: AuthRepository = AuthRepository.getInstance(application),
) : ViewModel() {

    private val _uiState = MutableStateFlow(ChannelVideosUiState(channel = channel))
    val uiState: StateFlow<ChannelVideosUiState> = _uiState.asStateFlow()

    init {
        observeSubscription()
        loadVideos()
    }

    fun refresh() {
        loadVideos()
    }

    fun toggleSubscribe() {
        viewModelScope.launch {
            libraryRepository.toggleSubscribeChannel(
                channelId = channel.channelId,
                title = channel.title,
                handle = channel.handle,
                avatarUrl = channel.avatarUrl.takeIf { it.isNotBlank() },
                subscriberCountText = channel.subscriberCountText,
                description = channel.description,
            )
        }
    }

    private fun observeSubscription() {
        viewModelScope.launch {
            authRepository.session
                .flatMapLatest { session ->
                    val ownerKey = session?.ownerKey
                    if (ownerKey == null) {
                        flowOf(false)
                    } else {
                        libraryRepository.observeIsSubscribed(ownerKey, channel.channelId)
                    }
                }
                .collect { subscribed ->
                    _uiState.update { it.copy(isSubscribed = subscribed) }
                }
        }
    }

    fun loadMore() {
        val state = _uiState.value
        val token = state.continuation ?: return
        if (state.isLoadingMore || state.isLoading) return

        viewModelScope.launch {
            _uiState.update { it.copy(isLoadingMore = true) }
            when (val result = repository.fetchChannelVideos(channel, continuation = token)) {
                is ExtractionResult.Success -> {
                    val filtered = result.data.videos.filter { video ->
                        video.channelId == null || video.channelId == channel.channelId
                    }
                    _uiState.update { current ->
                        val merged = (current.videos + filtered)
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

    private fun loadVideos() {
        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isLoading = true,
                    errorMessage = null,
                    videos = emptyList(),
                    continuation = null,
                )
            }
            when (val result = repository.fetchChannelVideos(channel)) {
                is ExtractionResult.Success -> {
                    val filtered = result.data.videos.filter { video ->
                        video.channelId == null || video.channelId == channel.channelId
                    }
                    _uiState.update {
                        it.copy(
                            channel = channel,
                            videos = filtered,
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

    companion object {
        fun factory(
            application: Application,
            channel: SubscriptionChannel,
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer { ChannelVideosViewModel(application, channel) }
        }
    }
}
