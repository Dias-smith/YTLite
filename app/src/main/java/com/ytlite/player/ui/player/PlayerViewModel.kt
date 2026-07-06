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
import com.ytlite.player.data.repository.ExtractionRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class PlayerViewModel(
    private val videoId: String,
    private val repository: ExtractionRepository = ExtractionRepository.getInstance(),
    private val jsEngine: JsExtractorEngine,
) : ViewModel() {

    private val _uiState = MutableStateFlow(PlayerUiState(isLoading = true))
    val uiState: StateFlow<PlayerUiState> = _uiState.asStateFlow()

    init {
        jsEngine.preloadAsync()
        loadPlayback()
    }

    fun loadPlayback() {
        viewModelScope.launch {
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

    companion object {
        fun factory(
            videoId: String,
            application: Application,
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                PlayerViewModel(
                    videoId = videoId,
                    jsEngine = JsExtractorEngine.getInstance(application),
                )
            }
        }
    }
}
