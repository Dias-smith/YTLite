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

class SubscriptionChannelsViewModel(
    application: Application,
    private val repository: SubscriptionsRepository = SubscriptionsRepository.getInstance(application),
) : ViewModel() {

    private val _uiState = MutableStateFlow(SubscriptionChannelsUiState())
    val uiState: StateFlow<SubscriptionChannelsUiState> = _uiState.asStateFlow()

    fun loadChannels() {
        viewModelScope.launch {
            YoutubeDiagnostics.d("ChannelsVM", "loadChannels start")
            _uiState.update {
                it.copy(
                    isLoading = true,
                    errorMessage = null,
                    channels = emptyList(),
                    continuation = null,
                )
            }
            when (val result = repository.fetchChannels()) {
                is ExtractionResult.Success -> {
                    YoutubeDiagnostics.d(
                        "ChannelsVM",
                        "loadChannels success channels=${result.data.channels.size} " +
                            "continuation=${result.data.continuation != null}",
                    )
                    _uiState.update {
                        it.copy(
                            channels = result.data.channels,
                            continuation = result.data.continuation,
                            isLoading = false,
                            errorMessage = null,
                        )
                    }
                }
                is ExtractionResult.Error -> {
                    YoutubeDiagnostics.e("ChannelsVM", "loadChannels error: ${result.message}", result.cause)
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
            when (val result = repository.fetchChannelsContinuation(token)) {
                is ExtractionResult.Success -> {
                    _uiState.update { current ->
                        val merged = (current.channels + result.data.channels)
                            .distinctBy { it.channelId }
                        current.copy(
                            channels = merged,
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
            initializer { SubscriptionChannelsViewModel(application) }
        }
    }
}
