package com.ytlite.player.ui.player

import android.app.Application
import android.net.Uri
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.ytlite.player.R
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
    private val application: Application,
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
            PlaybackManager.clearPlaybackError()
            _uiState.update {
                it.copy(
                    isLoading = true,
                    errorMessage = null,
                    playback = null,
                    selectedStreamUrl = null,
                )
            }
            when (val result = repository.fetchVideoPlayback(videoId)) {
                is ExtractionResult.Success -> {
                    val format = selectPlaybackFormat(result.data.formats)
                    Log.d(
                        TAG,
                        "formats=${result.data.formats.size} selected=" +
                            "${format?.itag ?: "none"} hasAudio=${format?.hasAudio} " +
                            "hasVideo=${format?.hasVideo}",
                    )
                    if (format == null) {
                        _uiState.update {
                            it.copy(
                                playback = result.data,
                                isLoading = false,
                                errorMessage = application.getString(R.string.player_format_unavailable),
                            )
                        }
                        return@launch
                    }
                    startPlayback(result.data, format)
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

    fun toggleDescription() {
        _uiState.update { it.copy(isDescriptionExpanded = !it.isDescriptionExpanded) }
    }

    private fun startPlayback(playback: VideoPlayback, format: StreamFormat) {
        val urlHost = runCatching { Uri.parse(format.url).host }.getOrNull()
        Log.d(
            TAG,
            "startPlayback videoId=${playback.videoId} itag=${format.itag} " +
                "mime=${format.mimeType} urlHost=$urlHost",
        )
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
                playback = playback,
                isLoading = false,
                selectedStreamUrl = format.url,
                errorMessage = null,
            )
        }
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
        private const val TAG = "PlayerViewModel"
        private const val PREFERRED_ITAG = 18

        internal fun selectPlaybackFormat(formats: List<StreamFormat>): StreamFormat? {
            formats.firstOrNull { it.itag == PREFERRED_ITAG }?.let { return it }

            formats
                .filter { it.hasAudio && it.hasVideo }
                .maxByOrNull { it.height }
                ?.let { return it }

            return formats.firstOrNull { it.hasAudio }
        }

        fun factory(
            videoId: String,
            application: Application,
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                PlayerViewModel(
                    videoId = videoId,
                    application = application,
                    libraryRepository = LibraryRepository.getInstance(application),
                    jsEngine = JsExtractorEngine.getInstance(application),
                )
            }
        }
    }
}
