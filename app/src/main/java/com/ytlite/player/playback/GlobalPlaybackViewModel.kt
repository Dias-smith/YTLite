package com.ytlite.player.playback

import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

@Immutable
data class GlobalPlaybackUiState(
    val nowPlaying: NowPlaying? = null,
    val isPlaying: Boolean = false,
    val positionMs: Long = 0,
    val durationMs: Long = 0,
    val showMiniPlayer: Boolean = false,
)

private data class PlaybackSnapshot(
    val nowPlaying: NowPlaying?,
    val isPlaying: Boolean,
    val positionMs: Long,
    val durationMs: Long,
    val ended: Boolean,
)

class GlobalPlaybackViewModel : ViewModel() {

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
    ) { snapshot, showMini ->
        GlobalPlaybackUiState(
            nowPlaying = if (snapshot.ended) null else snapshot.nowPlaying,
            isPlaying = snapshot.isPlaying && !snapshot.ended,
            positionMs = snapshot.positionMs,
            durationMs = snapshot.durationMs,
            showMiniPlayer = showMini && snapshot.nowPlaying != null && !snapshot.ended,
        )
    }.stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5_000),
        initialValue = GlobalPlaybackUiState(),
    )

    init {
        viewModelScope.launch {
            PlaybackManager.playbackEnded.collect { ended ->
                if (ended) {
                    showMiniPlayer.update { false }
                    PlaybackManager.stop()
                }
            }
        }

        viewModelScope.launch {
            while (isActive) {
                if (PlaybackManager.nowPlaying.value != null) {
                    PlaybackManager.refreshProgressAndPersist()
                }
                delay(1_000)
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
}
