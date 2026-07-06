package com.ytlite.player.ui.player

import android.app.Application
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.ytlite.player.data.js.JsExtractorEngine
import com.ytlite.player.data.model.ExtractionResult
import com.ytlite.player.data.model.StreamFormat
import com.ytlite.player.data.model.VideoPlayback
import com.ytlite.player.data.repository.ExtractionRepository
import com.ytlite.player.data.repository.LibraryRepository
import com.ytlite.player.playback.NowPlaying
import com.ytlite.player.playback.PlaybackManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class PlayerViewModel(
    private val videoId: String,
    private val repository: ExtractionRepository = ExtractionRepository.getInstance(),
    private val libraryRepository: LibraryRepository,
    private val jsEngine: JsExtractorEngine,
) : ViewModel() {

    private val _uiState = MutableStateFlow(PlayerUiState(isLoading = true))
    val uiState: StateFlow<PlayerUiState> = _uiState.asStateFlow()

    init {
        jsEngine.preloadAsync()
        val active = PlaybackManager.nowPlaying.value
        if (active?.videoId == videoId) {
            _uiState.update {
                it.copy(
                    isLoading = false,
                    playback = active.toStubPlayback(),
                    selectedStreamUrl = active.streamUrl,
                    showFormatPicker = false,
                    errorMessage = null,
                )
            }
        } else {
            loadPlayback()
        }
    }

    /** 可选：用户展开简介时再拉取完整元数据，避免播放中 WebView JS 阻塞主线程。 */
    fun loadFullMetadataIfNeeded() {
        val current = _uiState.value.playback ?: return
        if (current.description.isNotBlank() && current.viewCount > 0L) return
        loadPlaybackMetadataInBackground()
    }

    private fun loadPlaybackMetadataInBackground() {
        viewModelScope.launch(Dispatchers.IO) {
            when (val result = repository.fetchVideoPlayback(videoId)) {
                is ExtractionResult.Success -> {
                    _uiState.update {
                        it.copy(
                            playback = result.data,
                            errorMessage = null,
                        )
                    }
                }
                is ExtractionResult.Error -> Unit
            }
        }
    }

    fun loadPlayback() {
        viewModelScope.launch(Dispatchers.IO) {
            _uiState.update {
                it.copy(
                    isLoading = true,
                    errorMessage = null,
                    playback = null,
                    selectedStreamUrl = null,
                    showFormatPicker = false,
                    showStreamUrlDialog = false,
                )
            }
            when (val result = repository.fetchVideoPlayback(videoId)) {
                is ExtractionResult.Success -> {
                    _uiState.update {
                        it.copy(
                            playback = result.data,
                            isLoading = false,
                            errorMessage = null,
                            showFormatPicker = true,
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

    fun selectFormat(format: StreamFormat) {
        val playback = _uiState.value.playback ?: return
        val nowPlaying = NowPlaying(
            videoId = playback.videoId,
            title = playback.title,
            channelName = playback.channelName,
            streamUrl = format.url,
            thumbnailUrl = NowPlaying.thumbnailUrlFor(playback.videoId),
        )
        PlaybackManager.play(nowPlaying)
        viewModelScope.launch(Dispatchers.IO) {
            libraryRepository.addToHistory(nowPlaying)
        }
        _uiState.update {
            it.copy(
                selectedStreamUrl = format.url,
                showFormatPicker = false,
                showStreamUrlDialog = true,
            )
        }
    }

    fun dismissStreamUrlDialog() {
        _uiState.update { it.copy(showStreamUrlDialog = false) }
    }

    fun toggleDescription() {
        _uiState.update { it.copy(isDescriptionExpanded = !it.isDescriptionExpanded) }
    }

    private fun NowPlaying.toStubPlayback() = VideoPlayback(
        videoId = videoId,
        title = title,
        description = "",
        channelName = channelName,
        channelId = "",
        formats = emptyList(),
        durationSeconds = 0L,
        viewCount = 0L,
    )

    companion object {
        fun factory(
            videoId: String,
            application: Application,
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                PlayerViewModel(
                    videoId = videoId,
                    libraryRepository = LibraryRepository.getInstance(application),
                    jsEngine = JsExtractorEngine.getInstance(application),
                )
            }
        }
    }
}
