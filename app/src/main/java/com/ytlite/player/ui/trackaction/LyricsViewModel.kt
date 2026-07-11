package com.ytlite.player.ui.trackaction

import android.app.Application
import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.ytlite.player.data.model.CaptionTrack
import com.ytlite.player.data.parser.LyricLine
import com.ytlite.player.data.parser.VttLyricsParser
import com.ytlite.player.data.repository.CaptionRepository
import com.ytlite.player.data.repository.ExtractionRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Immutable
data class LyricsUiState(
    val isLoading: Boolean = true,
    val lines: List<LyricLine> = emptyList(),
    val tracks: List<CaptionTrack> = emptyList(),
    val selectedTrack: CaptionTrack? = null,
    val errorMessage: String? = null,
)

class LyricsViewModel(
    private val videoId: String,
    private val extractionRepository: ExtractionRepository,
    private val captionRepository: CaptionRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(LyricsUiState())
    val uiState: StateFlow<LyricsUiState> = _uiState.asStateFlow()

    init {
        loadLyrics()
    }

    fun loadLyrics(track: CaptionTrack? = null) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, errorMessage = null) }
            val playbackResult = withContext(Dispatchers.IO) {
                extractionRepository.fetchVideoPlayback(videoId)
            }
            val playback = when (playbackResult) {
                is com.ytlite.player.data.model.ExtractionResult.Success -> playbackResult.data
                is com.ytlite.player.data.model.ExtractionResult.Error -> {
                    _uiState.update {
                        it.copy(isLoading = false, errorMessage = "load_failed")
                    }
                    return@launch
                }
            }
            val tracks = playback.captionTracks
            if (tracks.isEmpty()) {
                _uiState.update { it.copy(isLoading = false, errorMessage = "empty") }
                return@launch
            }
            val selected = track ?: captionRepository.pickDefaultTrack(tracks)
            if (selected == null) {
                _uiState.update { it.copy(isLoading = false, errorMessage = "empty") }
                return@launch
            }
            val vtt = withContext(Dispatchers.IO) { captionRepository.fetchVtt(selected) }
            if (vtt.isNullOrBlank()) {
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        tracks = tracks,
                        selectedTrack = selected,
                        errorMessage = "load_failed",
                    )
                }
                return@launch
            }
            val lines = VttLyricsParser.parse(vtt)
            _uiState.update {
                it.copy(
                    isLoading = false,
                    lines = lines,
                    tracks = tracks,
                    selectedTrack = selected,
                    errorMessage = if (lines.isEmpty()) "empty" else null,
                )
            }
        }
    }

    companion object {
        fun factory(application: Application, videoId: String): ViewModelProvider.Factory =
            viewModelFactory {
                initializer {
                    LyricsViewModel(
                        videoId = videoId,
                        extractionRepository = ExtractionRepository.getInstance(),
                        captionRepository = CaptionRepository.getInstance(),
                    )
                }
            }
    }
}
