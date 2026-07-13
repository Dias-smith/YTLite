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
import com.ytlite.player.data.model.LibraryVideo
import com.ytlite.player.data.model.StreamFormat
import com.ytlite.player.data.model.VideoItem
import com.ytlite.player.data.model.VideoPlayback
import com.ytlite.player.data.repository.ExtractionRepository
import com.ytlite.player.data.repository.LibraryRepository
import com.ytlite.player.playback.NowPlaying
import com.ytlite.player.playback.PlayQueueRepository
import com.ytlite.player.playback.PlaybackManager
import com.ytlite.player.playback.PlaybackPrefetcher
import com.ytlite.player.playback.PlaybackTiming
import com.ytlite.player.playback.QueueItem
import com.ytlite.player.playback.UpNextCache
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

class PlayerViewModel(
    private val videoId: String,
    private val application: Application,
    private val repository: ExtractionRepository = ExtractionRepository.getInstance(),
    private val libraryRepository: LibraryRepository,
    private val jsEngine: JsExtractorEngine,
) : ViewModel() {

    private val _uiState = MutableStateFlow(PlayerUiState())
    val uiState: StateFlow<PlayerUiState> = _uiState.asStateFlow()

    private var lastExtractMessage: JSONObject? = null

    init {
        PlaybackTiming.beginSession(videoId)
        jsEngine.preloadAsync()
        val active = PlaybackManager.nowPlaying.value
        if (active?.videoId == videoId) {
            val cachedUpNext = UpNextCache.get(videoId)
            if (cachedUpNext != null) {
                lastExtractMessage = UpNextCache.getExtractMessage(videoId)
            }
            _uiState.update {
                it.copy(
                    isLoading = false,
                    isExtracting = false,
                    playback = active.toStubPlayback(),
                    selectedStreamUrl = active.streamUrl,
                    errorMessage = null,
                    upNextItems = cachedUpNext.orEmpty(),
                    upNextLoading = cachedUpNext == null,
                )
            }
            if (cachedUpNext != null) {
                seedQueue(cachedUpNext)
            } else {
                loadRelatedInBackground()
            }
        } else {
            val preview = PlayerLaunchPreview.consume(videoId)
            if (preview != null) {
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        isExtracting = true,
                        playback = preview.toStubPlayback(),
                        errorMessage = null,
                    )
                }
            } else {
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        isExtracting = true,
                        playback = videoPreview(videoId).toStubPlayback(),
                        errorMessage = null,
                    )
                }
            }
            loadPlayback()
        }
    }

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
                        it.copy(playback = result.data, errorMessage = null)
                    }
                }
                is ExtractionResult.Error -> Unit
            }
        }
    }

    fun loadPlayback() {
        viewModelScope.launch(Dispatchers.IO) {
            PlaybackManager.clearPlaybackError()
            val existingPlayback = _uiState.value.playback
            _uiState.update {
                it.copy(
                    isLoading = false,
                    isExtracting = true,
                    errorMessage = null,
                    playback = existingPlayback ?: videoPreview(videoId).toStubPlayback(),
                    selectedStreamUrl = null,
                )
            }
            runCatching { jsEngine.ensureReady() }
                .onSuccess { PlaybackTiming.logWebViewReady() }

            val bundle = PlaybackPrefetcher.consumeBundle(videoId)
                ?: repository.fetchVideoPlaybackBundle(videoId)
            PlaybackTiming.logExtractComplete()
            lastExtractMessage = bundle.rawMessage

            val playback = bundle.playback
            if (playback == null) {
                _uiState.update {
                    it.copy(
                        isExtracting = false,
                        errorMessage = bundle.errorMessage ?: application.getString(R.string.player_error),
                    )
                }
                return@launch
            }

            val audioOnly = shouldUseAudioOnly()
            val format = PlaybackFormatSelector.selectFormat(playback.formats, audioOnly)
            Log.d(
                TAG,
                "formats=${playback.formats.size} selected=" +
                    "${format?.itag ?: "none"} audioOnly=$audioOnly",
            )
            if (format == null) {
                _uiState.update {
                    it.copy(
                        playback = playback,
                        isExtracting = false,
                        errorMessage = application.getString(R.string.player_format_unavailable),
                    )
                }
                return@launch
            }
            startPlayback(playback, format)
            loadRelated(bundle.rawMessage)
        }
    }

    private suspend fun loadRelated(extractMessage: JSONObject?) {
        UpNextCache.get(videoId)?.let { cached ->
            val cachedMessage = UpNextCache.getExtractMessage(videoId) ?: extractMessage
            lastExtractMessage = cachedMessage
            _uiState.update {
                it.copy(
                    upNextItems = cached,
                    upNextLoading = false,
                    lastExtractMessage = cachedMessage,
                )
            }
            seedQueue(cached)
            return
        }

        _uiState.update { it.copy(upNextLoading = true) }
        when (val result = repository.fetchRelatedVideos(videoId, extractMessage)) {
            is ExtractionResult.Success -> {
                UpNextCache.put(videoId, result.data, extractMessage)
                lastExtractMessage = extractMessage
                _uiState.update {
                    it.copy(
                        upNextItems = result.data,
                        upNextLoading = false,
                        lastExtractMessage = extractMessage,
                    )
                }
                seedQueue(result.data)
            }
            is ExtractionResult.Error -> {
                _uiState.update { it.copy(upNextLoading = false) }
            }
        }
    }

    private fun loadRelatedInBackground() {
        viewModelScope.launch(Dispatchers.IO) {
            loadRelated(lastExtractMessage)
        }
    }

    private fun seedQueue(related: List<VideoItem>) {
        val current = PlaybackManager.nowPlaying.value ?: return
        val currentItem = QueueItem.fromNowPlaying(current)
        PlayQueueRepository.replaceCurrentAndAppend(
            current = currentItem,
            related = related.map { it.toQueueItem() },
            maxRelated = QUEUE_PREFILL_COUNT,
        )
    }

    fun toggleDescription() {
        _uiState.update { state ->
            if (!state.isDescriptionExpanded) {
                loadFullMetadataIfNeeded()
            }
            state.copy(isDescriptionExpanded = !state.isDescriptionExpanded)
        }
    }

    fun setSurfaceMode(mode: PlayerSurfaceMode) {
        _uiState.update { it.copy(surfaceMode = mode) }
        viewModelScope.launch(Dispatchers.IO) {
            val playback = ensurePlaybackWithFormats() ?: return@launch
            switchStreamForMode(mode, playback)
        }
    }

    fun prepareVideoForFullscreen(onReady: (PlayerSurfaceMode) -> Unit) {
        viewModelScope.launch(Dispatchers.IO) {
            _uiState.update { it.copy(surfaceMode = PlayerSurfaceMode.Video) }
            val playback = ensurePlaybackWithFormats()
            if (playback != null) {
                val format = PlaybackFormatSelector.selectVideoFormat(playback.formats)
                if (format != null) {
                    applyStreamSwitch(playback, format)
                }
            }
            val mode = _uiState.value.surfaceMode
            withContext(Dispatchers.Main) {
                onReady(mode)
            }
        }
    }

    private suspend fun ensurePlaybackWithFormats(): VideoPlayback? {
        val current = _uiState.value.playback ?: return null
        if (current.formats.isNotEmpty()) return current
        return when (val result = repository.fetchVideoPlayback(videoId)) {
            is ExtractionResult.Success -> {
                _uiState.update { it.copy(playback = result.data) }
                result.data
            }
            is ExtractionResult.Error -> null
        }
    }

    private fun switchStreamForMode(mode: PlayerSurfaceMode, playback: VideoPlayback) {
        val audioOnly = isAudioOnlyMode(mode)
        val format = PlaybackFormatSelector.selectFormat(playback.formats, audioOnly) ?: return
        applyStreamSwitch(playback, format)
    }

    private fun applyStreamSwitch(playback: VideoPlayback, format: StreamFormat) {
        if (format.url == _uiState.value.selectedStreamUrl) {
            _uiState.update { it.copy(playback = playback) }
            return
        }
        val nowPlaying = PlaybackManager.nowPlaying.value
        if (nowPlaying != null && nowPlaying.videoId == playback.videoId) {
            PlayQueueRepository.updateStreamUrl(playback.videoId, format.url)
            PlaybackManager.swapStreamUrl(nowPlaying.copy(streamUrl = format.url))
        }
        _uiState.update {
            it.copy(
                playback = playback,
                selectedStreamUrl = format.url,
            )
        }
    }

    private fun isAudioOnlyMode(mode: PlayerSurfaceMode): Boolean {
        return mode == PlayerSurfaceMode.AudioPowerSave
    }

    fun onUpNextClick(item: VideoItem) {
        viewModelScope.launch(Dispatchers.IO) {
            when (val result = repository.fetchVideoPlayback(item.videoId)) {
                is ExtractionResult.Success -> {
                    val format = PlaybackFormatSelector.selectVideoFormat(result.data.formats)
                        ?: return@launch
                    val nowPlaying = NowPlaying(
                        videoId = item.videoId,
                        title = item.title,
                        channelName = item.channelName,
                        streamUrl = format.url,
                        thumbnailUrl = item.thumbnailUrl,
                    )
                    val queueItem = item.toQueueItem(format.url)
                    PlayQueueRepository.addToEnd(queueItem)
                    PlayQueueRepository.setCurrentIndex(
                        PlayQueueRepository.state.value.items.indexOfFirst { it.videoId == item.videoId }
                            .coerceAtLeast(0),
                    )
                    PlaybackManager.play(nowPlaying)
                    _uiState.update {
                        it.copy(
                            playback = result.data,
                            selectedStreamUrl = format.url,
                            isLoading = false,
                            isExtracting = false,
                            errorMessage = null,
                        )
                    }
                }
                is ExtractionResult.Error -> Unit
            }
        }
    }

    fun showPlaylistPicker() {
        _uiState.update { it.copy(isPlaylistPickerVisible = true) }
    }

    fun dismissPlaylistPicker() {
        _uiState.update { it.copy(isPlaylistPickerVisible = false, showNewPlaylistDialog = false) }
    }

    fun showNewPlaylistDialog() {
        _uiState.update { it.copy(showNewPlaylistDialog = true) }
    }

    fun dismissNewPlaylistDialog() {
        _uiState.update { it.copy(showNewPlaylistDialog = false) }
    }

    fun saveToPlaylist(playlistId: String) {
        val playback = _uiState.value.playback ?: return
        viewModelScope.launch {
            libraryRepository.addTrackToPlaylist(
                playlistId = playlistId,
                video = LibraryVideo(
                    videoId = playback.videoId,
                    title = playback.title,
                    channelName = playback.channelName,
                    thumbnailUrl = NowPlaying.thumbnailUrlFor(playback.videoId),
                ),
            )
            dismissPlaylistPicker()
        }
    }

    fun createPlaylistAndSave(name: String) {
        val playback = _uiState.value.playback ?: return
        viewModelScope.launch {
            val ownerKey = libraryRepository.currentOwnerKey() ?: return@launch
            val playlistId = libraryRepository.createLocalPlaylist(ownerKey, name)
            libraryRepository.addTrackToPlaylist(
                playlistId = playlistId,
                video = LibraryVideo(
                    videoId = playback.videoId,
                    title = playback.title,
                    channelName = playback.channelName,
                    thumbnailUrl = NowPlaying.thumbnailUrlFor(playback.videoId),
                ),
            )
            dismissPlaylistPicker()
        }
    }

    fun libraryVideo(): LibraryVideo? {
        val playback = _uiState.value.playback ?: return null
        return LibraryVideo(
            videoId = playback.videoId,
            title = playback.title,
            channelName = playback.channelName,
            thumbnailUrl = NowPlaying.thumbnailUrlFor(playback.videoId),
        )
    }

    private fun startPlayback(
        playback: VideoPlayback,
        format: StreamFormat,
        updateQueue: Boolean = true,
    ) {
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
        if (updateQueue) {
            val currentItem = QueueItem.fromNowPlaying(nowPlaying)
            if (PlayQueueRepository.state.value.items.isEmpty()) {
                PlayQueueRepository.setQueue(listOf(currentItem))
            } else {
                PlayQueueRepository.updateStreamUrl(playback.videoId, format.url)
            }
        }
        PlaybackManager.play(nowPlaying)
        PlaybackTiming.logPlayStart()
        viewModelScope.launch(Dispatchers.IO) {
            libraryRepository.addToHistory(nowPlaying)
        }
        _uiState.update {
            it.copy(
                playback = playback,
                isLoading = false,
                isExtracting = false,
                selectedStreamUrl = format.url,
                errorMessage = null,
            )
        }
    }

    private fun shouldUseAudioOnly(): Boolean = isAudioOnlyMode(_uiState.value.surfaceMode)

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

    private fun VideoItem.toQueueItem(streamUrl: String? = null) = QueueItem(
        videoId = videoId,
        title = title,
        channelName = channelName,
        thumbnailUrl = thumbnailUrl,
        streamUrl = streamUrl,
        durationText = durationText,
        viewCountText = viewCountText,
        publishedTimeText = publishedTimeText,
    )

    companion object {
        private const val TAG = "PlayerViewModel"
        private const val QUEUE_PREFILL_COUNT = 20

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
