package com.ytlite.player.ui.trackaction

import android.app.Application
import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.ytlite.player.data.model.ExtractionResult
import com.ytlite.player.data.model.StreamFormat
import com.ytlite.player.data.model.isAudioOnly
import com.ytlite.player.data.model.resolvedContentLengthBytes
import com.ytlite.player.data.preferences.DownloadPreferences
import com.ytlite.player.data.repository.ExtractionRepository
import com.ytlite.player.download.DownloadEnqueueRequest
import com.ytlite.player.download.DownloadRepository
import com.ytlite.player.download.EnqueueResult
import com.ytlite.player.ui.player.PlaybackFormatSelector
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Immutable
data class DownloadFormatOption(
    val format: StreamFormat,
    val kind: DownloadFormatKind,
    val labelKey: DownloadFormatLabel,
)

enum class DownloadFormatKind { Music, Video }

enum class DownloadFormatLabel {
    MusicFast,
    MusicClassic,
    MusicHigh,
    VideoFast360,
    VideoHigh720,
    VideoBest1080,
    Generic,
}

@Immutable
data class DownloadFormatUiState(
    val isLoading: Boolean = true,
    val isEnqueueing: Boolean = false,
    val title: String = "",
    val channelName: String = "",
    val thumbnailUrl: String? = null,
    val durationSeconds: Long = 0L,
    val formats: List<StreamFormat> = emptyList(),
    val musicOptions: List<DownloadFormatOption> = emptyList(),
    val videoOptions: List<DownloadFormatOption> = emptyList(),
    val moreOptions: List<DownloadFormatOption> = emptyList(),
    val selectedItag: Int? = null,
    val showAllFormats: Boolean = false,
    val errorMessage: String? = null,
    val enqueueMessage: String? = null,
)

class DownloadFormatViewModel(
    private val videoId: String,
    private val extractionRepository: ExtractionRepository,
    private val downloadRepository: DownloadRepository,
    private val downloadPreferences: DownloadPreferences,
) : ViewModel() {

    private val _uiState = MutableStateFlow(DownloadFormatUiState())
    val uiState: StateFlow<DownloadFormatUiState> = _uiState.asStateFlow()

    init {
        loadFormats()
    }

    fun loadFormats() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, errorMessage = null) }
            val preferredItag = downloadPreferences.preferredItagFor(
                downloadPreferences.peekDefaultFormat(),
            )
            when (
                val result = withContext(Dispatchers.IO) {
                    extractionRepository.fetchVideoPlayback(videoId)
                }
            ) {
                is ExtractionResult.Success -> {
                    val playback = result.data
                    val formats = PlaybackFormatSelector.sortForDownload(
                        playback.formats.filter(::isDownloadableFormat),
                    ).map { format ->
                        val resolved = format.resolvedContentLengthBytes(playback.durationSeconds)
                        if (resolved > 0L && format.contentLengthBytes <= 0L) {
                            format.copy(contentLengthBytes = resolved)
                        } else {
                            format
                        }
                    }
                    val curated = curateOptions(formats)
                    val defaultItag = preferredItag?.takeIf { itag -> formats.any { it.itag == itag } }
                        ?: curated.videoOptions.lastOrNull()?.format?.itag
                        ?: curated.musicOptions.firstOrNull()?.format?.itag
                        ?: formats.firstOrNull()?.itag
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            title = playback.title,
                            channelName = playback.channelName,
                            thumbnailUrl = "https://i.ytimg.com/vi/${playback.videoId}/hqdefault.jpg",
                            durationSeconds = playback.durationSeconds,
                            formats = formats,
                            musicOptions = curated.musicOptions,
                            videoOptions = curated.videoOptions,
                            moreOptions = curated.moreOptions,
                            selectedItag = defaultItag,
                            errorMessage = if (formats.isEmpty()) "empty" else null,
                        )
                    }
                }
                is ExtractionResult.Error -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            formats = emptyList(),
                            musicOptions = emptyList(),
                            videoOptions = emptyList(),
                            moreOptions = emptyList(),
                            selectedItag = null,
                            errorMessage = "load_failed",
                        )
                    }
                }
            }
        }
    }

    fun selectItag(itag: Int) {
        _uiState.update { it.copy(selectedItag = itag) }
    }

    fun toggleShowAllFormats() {
        _uiState.update { it.copy(showAllFormats = !it.showAllFormats) }
    }

    fun selectedFormat(): StreamFormat? {
        val state = _uiState.value
        val itag = state.selectedItag ?: return null
        return state.formats.firstOrNull { it.itag == itag }
    }

    fun enqueueSelected(onDone: (EnqueueResult) -> Unit) {
        val state = _uiState.value
        val format = selectedFormat()
        if (format == null) {
            onDone(EnqueueResult.Error("select_format"))
            return
        }
        viewModelScope.launch {
            _uiState.update { it.copy(isEnqueueing = true) }
            val result = withContext(Dispatchers.IO) {
                downloadRepository.enqueue(
                    DownloadEnqueueRequest(
                        videoId = videoId,
                        title = state.title,
                        channelName = state.channelName,
                        thumbnailUrl = state.thumbnailUrl,
                        format = format,
                        durationSeconds = state.durationSeconds,
                    ),
                )
            }
            _uiState.update { it.copy(isEnqueueing = false) }
            onDone(result)
        }
    }

    private data class Curated(
        val musicOptions: List<DownloadFormatOption>,
        val videoOptions: List<DownloadFormatOption>,
        val moreOptions: List<DownloadFormatOption>,
    )

    private fun curateOptions(formats: List<StreamFormat>): Curated {
        val byItag = formats.associateBy { it.itag }
        val music = buildList {
            byItag[139]?.takeIf { it.isAudioOnly() }?.let {
                add(DownloadFormatOption(it, DownloadFormatKind.Music, DownloadFormatLabel.MusicFast))
            }
            byItag[140]?.takeIf { it.isAudioOnly() }?.let {
                add(
                    DownloadFormatOption(
                        it,
                        DownloadFormatKind.Music,
                        if (any { option -> option.format.itag == 139 }) {
                            DownloadFormatLabel.MusicClassic
                        } else {
                            DownloadFormatLabel.MusicFast
                        },
                    ),
                )
            }
            byItag[141]?.takeIf { it.isAudioOnly() }?.let {
                add(DownloadFormatOption(it, DownloadFormatKind.Music, DownloadFormatLabel.MusicHigh))
            }
            if (isEmpty()) {
                formats.filter { it.isAudioOnly() }
                    .take(2)
                    .forEach {
                        add(DownloadFormatOption(it, DownloadFormatKind.Music, DownloadFormatLabel.Generic))
                    }
            }
        }.take(2)

        val video = buildList {
            byItag[18]?.takeIf { it.hasAudio && it.hasVideo }?.let {
                add(DownloadFormatOption(it, DownloadFormatKind.Video, DownloadFormatLabel.VideoFast360))
            }
            byItag[22]?.takeIf { it.hasAudio && it.hasVideo }?.let {
                add(DownloadFormatOption(it, DownloadFormatKind.Video, DownloadFormatLabel.VideoHigh720))
            }
            byItag[37]?.takeIf { it.hasAudio && it.hasVideo }?.let {
                add(DownloadFormatOption(it, DownloadFormatKind.Video, DownloadFormatLabel.VideoBest1080))
            }
            if (isEmpty()) {
                formats.filter { it.hasAudio && it.hasVideo }
                    .sortedBy { it.height }
                    .take(2)
                    .forEach {
                        add(DownloadFormatOption(it, DownloadFormatKind.Video, DownloadFormatLabel.Generic))
                    }
            }
        }.take(2)

        val featuredItags = (music + video).map { it.format.itag }.toSet()
        val more = formats
            .filter { it.itag !in featuredItags }
            .map { format ->
                val kind = when {
                    format.isAudioOnly() -> DownloadFormatKind.Music
                    format.hasVideo -> DownloadFormatKind.Video
                    else -> DownloadFormatKind.Music
                }
                DownloadFormatOption(format, kind, DownloadFormatLabel.Generic)
            }

        return Curated(music, video, more)
    }

    private fun isDownloadableFormat(format: StreamFormat): Boolean {
        if (!format.hasAudio) return false
        val mime = format.mimeType.lowercase()
        val url = format.url.lowercase()
        if ("webm" in mime || url.contains(".webm")) return false
        if (
            "mpegurl" in mime ||
            "m3u8" in mime ||
            "application/vnd.apple.mpegurl" in mime ||
            url.contains(".m3u8") ||
            (url.contains("/manifest") && ("hls" in url || "m3u8" in url))
        ) {
            return false
        }
        return true
    }

    companion object {
        fun factory(application: Application, videoId: String): ViewModelProvider.Factory =
            viewModelFactory {
                initializer {
                    DownloadFormatViewModel(
                        videoId = videoId,
                        extractionRepository = ExtractionRepository.getInstance(),
                        downloadRepository = DownloadRepository.getInstance(application),
                        downloadPreferences = DownloadPreferences.getInstance(application),
                    )
                }
            }
    }
}
