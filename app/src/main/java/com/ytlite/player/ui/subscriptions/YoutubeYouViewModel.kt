package com.ytlite.player.ui.subscriptions

import android.app.Application
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.ytlite.player.data.auth.AuthRepository
import com.ytlite.player.data.auth.UserSession
import com.ytlite.player.data.model.ExtractionResult
import com.ytlite.player.data.repository.YoutubeYouRepository
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class YoutubeYouViewModel(
    application: Application,
    private val repository: YoutubeYouRepository = YoutubeYouRepository.getInstance(application),
    private val authRepository: AuthRepository = AuthRepository.getInstance(application),
) : ViewModel() {

    private val _uiState = MutableStateFlow(YoutubeYouUiState())
    val uiState: StateFlow<YoutubeYouUiState> = _uiState.asStateFlow()

    private var loadJob: Job? = null

    fun refreshIfNeeded(userId: String, channelId: String? = null) {
        val state = _uiState.value
        if (state.isLoading) return
        val shouldLoad = state.lastLoadedUserId != userId ||
            state.channelId != channelId ||
            !state.hasLoadedOnce
        if (!shouldLoad) return
        loadYouPage(userId)
    }

    fun refresh(userId: String? = null) {
        val resolvedUserId = userId
            ?: (authRepository.currentSession() as? UserSession.Authenticated)?.profile?.userId
            ?: return
        loadYouPage(resolvedUserId)
    }

    private fun loadYouPage(userId: String) {
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            val profile = (authRepository.currentSession() as? UserSession.Authenticated)?.profile
            _uiState.update {
                it.copy(
                    isLoading = true,
                    errorMessage = null,
                    needsYoutubeReauth = false,
                    displayName = profile?.displayName.orEmpty().ifBlank { it.displayName },
                    handle = profile?.handle ?: it.handle,
                    avatarUrl = profile?.avatarUrl ?: it.avatarUrl,
                    channelId = profile?.channelId ?: it.channelId,
                )
            }
            when (val result = repository.loadYouPage()) {
                is ExtractionResult.Success -> {
                    val data = result.data
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            errorMessage = if (data.needsYoutubeReauth) {
                                repository.youtubeReauthRequiredMessageForComparison()
                            } else {
                                null
                            },
                            needsYoutubeReauth = data.needsYoutubeReauth,
                            hasLoadedOnce = true,
                            lastLoadedUserId = userId,
                            displayName = data.channelTitle ?: profile?.displayName.orEmpty()
                                .ifBlank { it.displayName },
                            handle = data.channelHandle ?: profile?.handle ?: it.handle,
                            avatarUrl = data.channelAvatarUrl ?: profile?.avatarUrl ?: it.avatarUrl,
                            channelId = data.channelId ?: profile?.channelId ?: it.channelId,
                            subscriptions = data.subscriptions,
                            playlists = data.playlists,
                            history = data.history,
                            historyUnavailable = data.historyUnavailable,
                            watchLater = data.watchLater,
                            watchLaterPlaylistId = data.watchLaterPlaylistId,
                            watchLaterUnavailable = data.watchLaterUnavailable,
                            liked = data.liked,
                            likedPlaylistId = data.likedPlaylistId,
                            yourVideos = data.yourVideos,
                            uploadsPlaylistId = data.uploadsPlaylistId,
                        )
                    }
                }
                is ExtractionResult.Error -> {
                    val needsReauth =
                        result.message == repository.youtubeReauthRequiredMessageForComparison()
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            errorMessage = result.message,
                            needsYoutubeReauth = needsReauth,
                            hasLoadedOnce = true,
                            lastLoadedUserId = userId,
                        )
                    }
                }
            }
        }
    }

    companion object {
        fun factory(application: Application): ViewModelProvider.Factory = viewModelFactory {
            initializer { YoutubeYouViewModel(application) }
        }
    }
}
