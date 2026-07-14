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
import com.ytlite.player.playback.RelatedCacheKind
import com.ytlite.player.playback.UpNextCache
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.map
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
            val cachedWww = UpNextCache.get(videoId, RelatedCacheKind.Www)
            val cachedMusic = UpNextCache.get(videoId, RelatedCacheKind.Music)
            if (cachedWww != null || cachedMusic != null) {
                lastExtractMessage = UpNextCache.getExtractMessage(videoId, RelatedCacheKind.Www)
                    ?: UpNextCache.getExtractMessage(videoId, RelatedCacheKind.Music)
            }
            _uiState.update {
                it.copy(
                    isLoading = false,
                    isExtracting = false,
                    playback = active.toStubPlayback(),
                    selectedStreamUrl = active.streamUrl,
                    errorMessage = null,
                    recommendedItems = cachedMusic.orEmpty(),
                    recommendLoading = cachedMusic == null,
                    upNextItems = cachedWww.orEmpty(),
                    upNextLoading = cachedWww == null,
                )
            }
            // Same track reopen: refresh Related (Music); seed Up next from www only outside playlist.
            val inPlaylistContext = PlayQueueRepository.state.value.sourcePlaylistId != null
            if (cachedWww == null || cachedMusic == null) {
                loadRelatedInBackground(shouldSeedQueue = !inPlaylistContext)
            } else if (!inPlaylistContext && PlayQueueRepository.state.value.items.size <= 1) {
                seedQueue(cachedWww)
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
        observeNowPlayingChanges()
    }

    private fun observeNowPlayingChanges() {
        viewModelScope.launch {
            PlaybackManager.nowPlaying
                .filterNotNull()
                .map { it.videoId to it }
                .distinctUntilChanged { old, new -> old.first == new.first }
                .collect { (_, nowPlaying) ->
                    val currentId = _uiState.value.playback?.videoId
                    if (currentId == nowPlaying.videoId) {
                        if (_uiState.value.selectedStreamUrl != nowPlaying.streamUrl) {
                            _uiState.update { it.copy(selectedStreamUrl = nowPlaying.streamUrl) }
                        }
                        return@collect
                    }
                    syncToNowPlaying(nowPlaying)
                }
        }
    }

    private fun syncToNowPlaying(nowPlaying: NowPlaying) {
        _uiState.update {
            it.copy(
                playback = enrichPlaybackStub(nowPlaying),
                selectedStreamUrl = nowPlaying.streamUrl,
                isExtracting = false,
                errorMessage = null,
            )
        }
        loadPlaybackMetadataFor(nowPlaying.videoId)
        loadRelatedForVideo(nowPlaying.videoId, seedQueue = false)
    }

    private fun enrichPlaybackStub(nowPlaying: NowPlaying): VideoPlayback {
        _uiState.value.recommendedItems
            .firstOrNull { it.videoId == nowPlaying.videoId }
            ?.let { return it.toMetadataPlayback() }
        _uiState.value.upNextItems
            .firstOrNull { it.videoId == nowPlaying.videoId }
            ?.let { return it.toMetadataPlayback() }
        PlayQueueRepository.state.value.items
            .firstOrNull { it.videoId == nowPlaying.videoId }
            ?.let { item ->
                return VideoPlayback(
                    videoId = item.videoId,
                    title = item.title,
                    description = "",
                    channelName = item.channelName,
                    channelId = "",
                    formats = emptyList(),
                    durationSeconds = 0L,
                    viewCount = 0L,
                )
            }
        return nowPlaying.toStubPlayback()
    }

    private fun VideoItem.toMetadataPlayback() = VideoPlayback(
        videoId = videoId,
        title = title,
        description = "",
        channelName = channelName,
        channelId = channelId.orEmpty(),
        formats = emptyList(),
        durationSeconds = 0L,
        viewCount = 0L,
    )

    fun loadFullMetadataIfNeeded() {
        val current = _uiState.value.playback ?: return
        if (current.description.isNotBlank() && current.viewCount > 0L) return
        loadPlaybackMetadataInBackground()
    }

    private fun loadPlaybackMetadataInBackground() {
        val targetVideoId = _uiState.value.playback?.videoId ?: return
        loadPlaybackMetadataFor(targetVideoId)
    }

    private fun loadPlaybackMetadataFor(targetVideoId: String) {
        viewModelScope.launch(Dispatchers.IO) {
            when (val result = repository.fetchVideoPlayback(targetVideoId)) {
                is ExtractionResult.Success -> {
                    if (PlaybackManager.nowPlaying.value?.videoId != targetVideoId) return@launch
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
            val inPlaylistContext = PlayQueueRepository.state.value.sourcePlaylistId != null
            loadRelated(bundle.rawMessage, shouldSeedQueue = !inPlaylistContext)
        }
    }

    private suspend fun loadRelated(extractMessage: JSONObject?, shouldSeedQueue: Boolean = true) {
        val targetVideoId = _uiState.value.playback?.videoId ?: videoId
        loadRelatedForVideo(targetVideoId, extractMessage, shouldSeedQueue)
    }

    private fun loadRelatedForVideo(
        targetVideoId: String,
        extractMessage: JSONObject? = lastExtractMessage,
        seedQueue: Boolean = true,
    ) {
        viewModelScope.launch(Dispatchers.IO) {
            loadRelatedForVideoSuspend(targetVideoId, extractMessage, seedQueue)
        }
    }

    private suspend fun loadRelatedForVideoSuspend(
        targetVideoId: String,
        extractMessage: JSONObject?,
        shouldSeedQueue: Boolean,
    ) {
        val allowSeed = shouldSeedQueue &&
            PlayQueueRepository.state.value.sourcePlaylistId == null

        val cachedWww = UpNextCache.get(targetVideoId, RelatedCacheKind.Www)
        val cachedMusic = UpNextCache.get(targetVideoId, RelatedCacheKind.Music)
        if (cachedWww != null || cachedMusic != null) {
            val cachedMessage = UpNextCache.getExtractMessage(targetVideoId, RelatedCacheKind.Www)
                ?: UpNextCache.getExtractMessage(targetVideoId, RelatedCacheKind.Music)
                ?: extractMessage
            if (targetVideoId == (_uiState.value.playback?.videoId ?: videoId)) {
                lastExtractMessage = cachedMessage
            }
            _uiState.update {
                it.copy(
                    recommendedItems = cachedMusic.orEmpty().ifEmpty { it.recommendedItems },
                    recommendLoading = cachedMusic == null,
                    upNextItems = cachedWww.orEmpty().ifEmpty { it.upNextItems },
                    upNextLoading = cachedWww == null,
                    lastExtractMessage = cachedMessage,
                )
            }
            if (allowSeed && cachedWww != null) {
                seedQueue(cachedWww)
            }
            if (cachedWww != null && cachedMusic != null) {
                return
            }
        }

        _uiState.update {
            it.copy(
                recommendLoading = cachedMusic == null,
                upNextLoading = cachedWww == null,
            )
        }

        coroutineScope {
            val wwwDeferred = async {
                if (cachedWww != null) {
                    ExtractionResult.Success(cachedWww)
                } else {
                    repository.fetchWwwRelatedVideos(targetVideoId, extractMessage)
                }
            }
            val musicDeferred = async {
                if (cachedMusic != null) {
                    ExtractionResult.Success(cachedMusic)
                } else {
                    repository.fetchMusicRelatedVideos(targetVideoId)
                }
            }
            val wwwResult = wwwDeferred.await()
            val musicResult = musicDeferred.await()

            val wwwItems = (wwwResult as? ExtractionResult.Success)?.data.orEmpty()
            val musicItems = (musicResult as? ExtractionResult.Success)?.data.orEmpty()

            if (wwwItems.isNotEmpty()) {
                UpNextCache.put(targetVideoId, wwwItems, extractMessage, RelatedCacheKind.Www)
            }
            if (musicItems.isNotEmpty()) {
                UpNextCache.put(targetVideoId, musicItems, null, RelatedCacheKind.Music)
            }

            if (targetVideoId == (_uiState.value.playback?.videoId ?: videoId)) {
                lastExtractMessage = extractMessage
            }
            _uiState.update {
                it.copy(
                    recommendedItems = musicItems.ifEmpty { it.recommendedItems },
                    recommendLoading = false,
                    upNextItems = wwwItems.ifEmpty { it.upNextItems },
                    upNextLoading = false,
                    lastExtractMessage = extractMessage,
                )
            }
            if (allowSeed && wwwItems.isNotEmpty()) {
                seedQueue(wwwItems)
            }
        }
    }

    private fun loadRelatedInBackground(shouldSeedQueue: Boolean = true) {
        viewModelScope.launch(Dispatchers.IO) {
            loadRelated(lastExtractMessage, shouldSeedQueue = shouldSeedQueue)
        }
    }

    private fun seedQueue(related: List<VideoItem>) {
        if (PlayQueueRepository.state.value.sourcePlaylistId != null) return
        val nowPlaying = PlaybackManager.nowPlaying.value
        val playback = _uiState.value.playback
        val currentItem = when {
            nowPlaying != null -> QueueItem.fromNowPlaying(nowPlaying)
            playback != null -> QueueItem(
                videoId = playback.videoId,
                title = playback.title,
                channelName = playback.channelName,
                thumbnailUrl = NowPlaying.thumbnailUrlFor(playback.videoId),
                streamUrl = _uiState.value.selectedStreamUrl,
            )
            else -> return
        }
        PlayQueueRepository.replaceCurrentAndAppend(
            current = currentItem,
            related = related.map { it.toQueueItem() },
            maxRelated = QUEUE_PREFILL_COUNT,
            clearSourcePlaylist = true,
        )
        PlaybackManager.syncRepeatMode()
    }

    fun selectListTab(tab: PlayerListTab) {
        _uiState.update { it.copy(selectedListTab = tab) }
    }

    fun onQueueItemClick(item: QueueItem) {
        viewModelScope.launch(Dispatchers.IO) {
            val index = PlayQueueRepository.state.value.items
                .indexOfFirst { it.videoId == item.videoId }
            if (index < 0) return@launch
            PlayQueueRepository.setCurrentIndex(index)
            val streamUrl = item.streamUrl
            if (!streamUrl.isNullOrBlank()) {
                PlaybackManager.play(item.toNowPlaying(streamUrl))
                return@launch
            }
            when (val result = repository.fetchVideoPlayback(item.videoId)) {
                is ExtractionResult.Success -> {
                    val format = PlaybackFormatSelector.selectVideoFormat(result.data.formats)
                        ?: return@launch
                    PlayQueueRepository.updateStreamUrl(item.videoId, format.url, format.itag)
                    val nowPlaying = item.toNowPlaying(format.url).copy(
                        itag = format.itag,
                        durationMs = result.data.durationSeconds.takeIf { it > 0L }?.times(1000L),
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

    fun onRecommendClick(item: VideoItem) {
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
                        itag = format.itag,
                        durationMs = result.data.durationSeconds.takeIf { it > 0L }?.times(1000L),
                    )
                    val currentItem = QueueItem.fromNowPlaying(nowPlaying)
                    val related = when (val relatedResult = repository.fetchMusicRelatedVideos(item.videoId)) {
                        is ExtractionResult.Success -> {
                            UpNextCache.put(
                                item.videoId,
                                relatedResult.data,
                                null,
                                RelatedCacheKind.Music,
                            )
                            relatedResult.data
                        }
                        is ExtractionResult.Error -> emptyList()
                    }
                    PlayQueueRepository.replaceCurrentAndAppend(
                        current = currentItem,
                        related = related.map { it.toQueueItem() },
                        maxRelated = QUEUE_PREFILL_COUNT,
                        clearSourcePlaylist = true,
                    )
                    PlaybackManager.play(nowPlaying)
                    PlaybackManager.syncRepeatMode()
                    // Also refresh www related for Up next tab enrich, without reseeding over Music queue.
                    val wwwRelated = when (
                        val wwwResult = repository.fetchWwwRelatedVideos(item.videoId)
                    ) {
                        is ExtractionResult.Success -> {
                            UpNextCache.put(
                                item.videoId,
                                wwwResult.data,
                                null,
                                RelatedCacheKind.Www,
                            )
                            wwwResult.data
                        }
                        is ExtractionResult.Error -> emptyList()
                    }
                    _uiState.update {
                        it.copy(
                            playback = result.data,
                            selectedStreamUrl = format.url,
                            isLoading = false,
                            isExtracting = false,
                            errorMessage = null,
                            recommendedItems = related,
                            recommendLoading = false,
                            upNextItems = wwwRelated.ifEmpty { related },
                            upNextLoading = false,
                            selectedListTab = PlayerListTab.UpNext,
                        )
                    }
                }
                is ExtractionResult.Error -> Unit
            }
        }
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
        val queueItem = PlayQueueRepository.state.value.items
            .firstOrNull { it.videoId == item.videoId }
            ?: item.toQueueItem()
        onQueueItemClick(queueItem)
    }

    fun showPlaylistPicker() {
        _uiState.update {
            it.copy(
                isPlaylistPickerVisible = true,
                playlistSaveItems = null,
            )
        }
    }

    fun showSaveCurrentListPlaylistPicker() {
        val items = currentListAsLibraryVideos()
        if (items.isEmpty()) return
        _uiState.update {
            it.copy(
                isPlaylistPickerVisible = true,
                playlistSaveItems = items,
            )
        }
    }

    fun dismissPlaylistPicker() {
        _uiState.update {
            it.copy(
                isPlaylistPickerVisible = false,
                showNewPlaylistDialog = false,
                playlistSaveItems = null,
            )
        }
    }

    fun showNewPlaylistDialog() {
        _uiState.update { it.copy(showNewPlaylistDialog = true) }
    }

    fun dismissNewPlaylistDialog() {
        _uiState.update { it.copy(showNewPlaylistDialog = false) }
    }

    fun saveToPlaylist(playlistId: String) {
        val batch = _uiState.value.playlistSaveItems
        if (batch != null) {
            viewModelScope.launch {
                libraryRepository.addTracksToPlaylist(playlistId, batch)
                dismissPlaylistPicker()
            }
            return
        }
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
        if (name.isBlank()) return
        val batch = _uiState.value.playlistSaveItems
        viewModelScope.launch {
            val ownerKey = libraryRepository.currentOwnerKey() ?: return@launch
            val playlistId = libraryRepository.createLocalPlaylist(ownerKey, name)
            if (batch != null) {
                libraryRepository.addTracksToPlaylist(playlistId, batch)
            } else {
                val playback = _uiState.value.playback ?: return@launch
                libraryRepository.addTrackToPlaylist(
                    playlistId = playlistId,
                    video = LibraryVideo(
                        videoId = playback.videoId,
                        title = playback.title,
                        channelName = playback.channelName,
                        thumbnailUrl = NowPlaying.thumbnailUrlFor(playback.videoId),
                    ),
                )
            }
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

    private fun currentListAsLibraryVideos(): List<LibraryVideo> {
        return when (_uiState.value.selectedListTab) {
            PlayerListTab.UpNext -> PlayQueueRepository.state.value.items.map { it.toLibraryVideo() }
            PlayerListTab.Recommend -> _uiState.value.recommendedItems.map { it.toLibraryVideo() }
            PlayerListTab.Lyrics -> emptyList()
        }
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
            itag = format.itag,
            durationMs = playback.durationSeconds.takeIf { it > 0L }?.times(1000L),
        )
        if (updateQueue) {
            val currentItem = QueueItem.fromNowPlaying(nowPlaying)
            val queue = PlayQueueRepository.state.value
            val existingIndex = queue.items.indexOfFirst { it.videoId == playback.videoId }
            when {
                existingIndex >= 0 -> {
                    if (existingIndex != queue.currentIndex) {
                        PlayQueueRepository.setCurrentIndex(existingIndex)
                    }
                    PlayQueueRepository.updateStreamUrl(playback.videoId, format.url, format.itag)
                }
                // Album/playlist/channel context: never wipe Up next down to a single related seed.
                queue.sourcePlaylistId != null -> {
                    PlayQueueRepository.syncCurrentInPlaylistContext(currentItem)
                }
                else -> {
                    // New track opened from detail: keep it at the front before related are seeded.
                    PlayQueueRepository.setQueue(
                        items = listOf(currentItem),
                        startIndex = 0,
                        preservePlaybackMode = true,
                    )
                }
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

    private fun QueueItem.toLibraryVideo() = LibraryVideo(
        videoId = videoId,
        title = title,
        channelName = channelName,
        thumbnailUrl = thumbnailUrl,
        durationText = durationText,
        viewCountText = viewCountText,
        publishedTimeText = publishedTimeText,
        album = album,
        year = year,
    )

    private fun VideoItem.toLibraryVideo() = LibraryVideo(
        videoId = videoId,
        title = title,
        channelName = channelName,
        channelId = channelId,
        thumbnailUrl = thumbnailUrl,
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
