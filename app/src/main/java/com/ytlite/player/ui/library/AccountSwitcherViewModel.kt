package com.ytlite.player.ui.library

import android.app.Application
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.ytlite.player.data.auth.AuthRepository
import com.ytlite.player.data.auth.OwnedYoutubeChannel
import com.ytlite.player.data.repository.OwnedChannelsRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class AccountChannelsUiState(
    val isLoading: Boolean = false,
    val channels: List<OwnedYoutubeChannel> = emptyList(),
    val activeChannelId: String? = null,
    val errorMessage: String? = null,
)

class AccountSwitcherViewModel(
    application: Application,
    private val authRepository: AuthRepository = AuthRepository.getInstance(application),
    private val ownedChannelsRepository: OwnedChannelsRepository =
        OwnedChannelsRepository.getInstance(application),
) : ViewModel() {

    private val _uiState = MutableStateFlow(AccountChannelsUiState())
    val uiState: StateFlow<AccountChannelsUiState> = _uiState.asStateFlow()

    fun onSheetOpened(activeChannelId: String?) {
        _uiState.value = AccountChannelsUiState(activeChannelId = activeChannelId)
        loadChannels()
    }

    fun onSheetClosed() {
        _uiState.value = AccountChannelsUiState()
    }

    fun loadChannels() {
        if (_uiState.value.isLoading) return
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, errorMessage = null) }
            ownedChannelsRepository.fetchOwnedChannels()
                .onSuccess { channels ->
                    val activeId = authRepository.getActiveChannelId()
                        ?: channels.firstOrNull()?.channelId
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            channels = channels,
                            activeChannelId = activeId,
                        )
                    }
                }
                .onFailure { error ->
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            errorMessage = error.message ?: "无法加载频道列表",
                        )
                    }
                }
        }
    }

    fun selectChannel(channel: OwnedYoutubeChannel) {
        viewModelScope.launch {
            authRepository.selectYoutubeChannel(channel)
            _uiState.update { it.copy(activeChannelId = channel.channelId) }
        }
    }

    companion object {
        fun factory(application: Application): ViewModelProvider.Factory = viewModelFactory {
            initializer { AccountSwitcherViewModel(application) }
        }
    }
}
