package com.ytlite.player.playback

import android.app.Application
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ytlite.player.data.model.ExtractionResult
import com.ytlite.player.data.repository.ExtractionRepository
import com.ytlite.player.ui.player.PlaybackFormatSelector
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory

@androidx.compose.runtime.Immutable
data class GlobalPlaybackUiState(
    val nowPlaying: NowPlaying? = null,
    val isPlaying: Boolean = false,
    val positionMs: Long = 0,
    val durationMs: Long = 0,
    val showMiniPlayer: Boolean = false,
    val queueState: PlayQueueState = PlayQueueState(),
)

private data class PlaybackSnapshot(
    val nowPlaying: NowPlaying?,
    val isPlaying: Boolean,
    val positionMs: Long,
    val durationMs: Long,
    val ended: Boolean,
)

class GlobalPlaybackViewModel(
    private val extractionRepository: ExtractionRepository = ExtractionRepository.getInstance(),
) : ViewModel() {

    private val showMiniPlayer = MutableStateFlow(false)

    private val playbackSnapshot = combine(
        PlaybackManager.nowPlaying,
        PlaybackManager.isPlaying,
        PlaybackManager.positionMs,
        PlaybackManager.durationMs,
        PlaybackManager.playbackEnded,
    ) { nowPlaying, isPlaying, position, duration, ended ->
        PlaybackSnapshot(nowPlaying, isPlaying, position, duration, ended)
    }

    val uiState: StateFlow<GlobalPlaybackUiState> = combine(
        playbackSnapshot,
        showMiniPlayer,
        PlayQueueRepository.state,
    ) { snapshot, showMini, queueState ->
        GlobalPlaybackUiState(
            nowPlaying = if (snapshot.ended && !queueState.hasNext) null else snapshot.nowPlaying,
            isPlaying = snapshot.isPlaying && !snapshot.ended,
            positionMs = snapshot.positionMs,
            durationMs = snapshot.durationMs,
            showMiniPlayer = showMini && snapshot.nowPlaying != null && !snapshot.ended,
            queueState = queueState,
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = GlobalPlaybackUiState(),
    )

    init {
        viewModelScope.launch {
            PlaybackManager.playbackEnded.collect { ended ->
                if (!ended) return@collect
                handlePlaybackEnded()
            }
        }

        viewModelScope.launch {
            while (isActive) {
                if (PlaybackManager.nowPlaying.value != null) {
                    PlaybackManager.refreshProgressAndPersist()
                }
                kotlinx.coroutines.delay(1_000)
            }
        }
    }

    private suspend fun handlePlaybackEnded() {
        val advanced = PlayQueueRepository.advanceToNext()
        if (advanced == null) {
            showMiniPlayer.update { false }
            PlaybackManager.stop()
            PlayQueueRepository.clear()
            return
        }
        PlaybackManager.resetPlaybackEnded()
        val streamUrl = advanced.streamUrl
        if (!streamUrl.isNullOrBlank()) {
            PlaybackManager.play(advanced.toNowPlaying(streamUrl))
            return
        }
        when (val result = withContext(Dispatchers.IO) {
            extractionRepository.fetchVideoPlayback(advanced.videoId)
        }) {
            is ExtractionResult.Success -> {
                val format = PlaybackFormatSelector.selectVideoFormat(result.data.formats)
                if (format == null) {
                    Log.w(TAG, "No format for queue item ${advanced.videoId}")
                    handlePlaybackEnded()
                    return
                }
                PlayQueueRepository.updateStreamUrl(advanced.videoId, format.url)
                PlaybackManager.play(advanced.toNowPlaying(format.url))
            }
            is ExtractionResult.Error -> {
                Log.w(TAG, "Failed to resolve queue item ${advanced.videoId}: ${result.message}")
                handlePlaybackEnded()
            }
        }
    }

    fun onLeavePlayerScreen() {
        if (PlaybackManager.nowPlaying.value != null) {
            showMiniPlayer.update { true }
        }
    }

    fun onEnterPlayerScreen() {
        showMiniPlayer.update { false }
    }

    fun togglePlayPause() {
        PlaybackManager.togglePlayPause()
    }

    fun play(nowPlaying: NowPlaying) {
        PlaybackManager.play(nowPlaying)
    }

    fun skipToNext() {
        viewModelScope.launch {
            val queueState = PlayQueueRepository.state.value
            if (queueState.hasNext) {
                val nextIndex = queueState.currentIndex + 1
                val nextItem = queueState.items[nextIndex]
                PlayQueueRepository.setCurrentIndex(nextIndex)
                playQueueItem(nextItem)
            }
        }
    }

    fun openQueueSheet() {
        // handled in UI layer
    }

    fun playQueueItem(item: QueueItem) {
        viewModelScope.launch {
            val streamUrl = item.streamUrl
            if (!streamUrl.isNullOrBlank()) {
                PlaybackManager.play(item.toNowPlaying(streamUrl))
                return@launch
            }
            when (val result = withContext(Dispatchers.IO) {
                extractionRepository.fetchVideoPlayback(item.videoId)
            }) {
                is ExtractionResult.Success -> {
                    val format = PlaybackFormatSelector.selectVideoFormat(result.data.formats)
                        ?: return@launch
                    PlayQueueRepository.updateStreamUrl(item.videoId, format.url)
                    PlaybackManager.play(item.toNowPlaying(format.url))
                }
                is ExtractionResult.Error -> Unit
            }
        }
    }

    fun reorderQueue(fromIndex: Int, toIndex: Int) {
        PlayQueueRepository.moveItem(fromIndex, toIndex)
        PlaybackManager.syncQueueOrder(PlayQueueRepository.state.value.items)
    }

    companion object {
        private const val TAG = "GlobalPlaybackVM"

        fun factory(application: Application): androidx.lifecycle.ViewModelProvider.Factory =
            viewModelFactory {
                initializer {
                    ExtractionRepository.init(application)
                    GlobalPlaybackViewModel()
                }
            }
    }
}
