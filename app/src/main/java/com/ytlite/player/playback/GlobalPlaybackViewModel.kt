package com.ytlite.player.playback

import android.app.Application
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ytlite.player.data.model.CaptionTrack
import com.ytlite.player.data.model.ExtractionResult
import com.ytlite.player.data.model.StreamFormat
import com.ytlite.player.data.model.VideoPlayback
import com.ytlite.player.data.preferences.PlaybackPreferences
import com.ytlite.player.data.repository.CaptionRepository
import com.ytlite.player.data.repository.ExtractionRepository
import com.ytlite.player.ui.player.PlaybackFormatSelector
import com.ytlite.player.ui.player.PlayerLaunchPreview
import com.ytlite.player.ui.player.toVideoItem
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import java.io.File

@androidx.compose.runtime.Immutable
data class GlobalPlaybackUiState(
    val nowPlaying: NowPlaying? = null,
    val isPlaying: Boolean = false,
    val positionMs: Long = 0,
    val durationMs: Long = 0,
    val showMiniPlayer: Boolean = false,
    val queueState: PlayQueueState = PlayQueueState(),
)

@androidx.compose.runtime.Immutable
data class ExpandedPlayerUiState(
    val captionTracks: List<CaptionTrack> = emptyList(),
    val selectedCaption: CaptionTrack? = null,
    val subtitlesEnabled: Boolean = false,
    val isLiked: Boolean = false,
    val isDisliked: Boolean = false,
    val showSettingsSheet: Boolean = false,
    val showCaptionSheet: Boolean = false,
    val currentFormats: List<StreamFormat> = emptyList(),
    val playbackSpeed: Float = PlaybackPreferences.DEFAULT_SPEED,
    val preferredItag: Int? = null,
    val pendingSnackbar: String? = null,
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
    private val captionRepository: CaptionRepository = CaptionRepository.getInstance(),
    private val playbackPreferences: PlaybackPreferences? = null,
    private val libraryRepository: com.ytlite.player.data.repository.LibraryRepository? = null,
    private val authRepository: com.ytlite.player.data.auth.AuthRepository? = null,
    private val playbackSessionStore: PlaybackSessionStore? = null,
    private val appContext: android.content.Context? = null,
) : ViewModel() {

    private val showMiniPlayer = MutableStateFlow(false)
    private val expandedState = MutableStateFlow(ExpandedPlayerUiState())
    private var restoredStartPositionMs: Long = 0L
    private var sessionRestoreCompleted = false

    val expandedUiState: StateFlow<ExpandedPlayerUiState> = expandedState.asStateFlow()

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
            nowPlaying = if (snapshot.ended && !queueState.hasNext && queueState.repeatMode == QueueRepeatMode.OFF) {
                null
            } else {
                snapshot.nowPlaying
            },
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
            restorePlaybackSession()
            sessionRestoreCompleted = true
        }

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

        viewModelScope.launch {
            @OptIn(FlowPreview::class)
            combine(
                PlayQueueRepository.state,
                PlaybackManager.nowPlaying,
                PlaybackManager.positionMs,
                PlaybackManager.durationMs,
            ) { queue, nowPlaying, positionMs, durationMs ->
                queue to Triple(nowPlaying, positionMs, durationMs)
            }
                .debounce(500)
                .collect { (queue, triple) ->
                    if (!sessionRestoreCompleted) return@collect
                    val (nowPlaying, positionMs, durationMs) = triple
                    persistPlaybackSession(queue, nowPlaying, positionMs, durationMs)
                }
        }

        playbackPreferences?.let { prefs ->
            viewModelScope.launch {
                prefs.playbackSpeed.collect { speed ->
                    expandedState.update { it.copy(playbackSpeed = speed) }
                    PlaybackManager.setPlaybackSpeed(speed)
                }
            }
            viewModelScope.launch {
                prefs.preferredItag.collect { itag ->
                    expandedState.update { it.copy(preferredItag = itag) }
                }
            }
        }

        viewModelScope.launch {
            PlaybackManager.nowPlaying.collect { nowPlaying ->
                if (nowPlaying != null) {
                    loadPlaybackExtras(nowPlaying.videoId)
                } else {
                    expandedState.update {
                        it.copy(
                            captionTracks = emptyList(),
                            selectedCaption = null,
                            subtitlesEnabled = false,
                            currentFormats = emptyList(),
                            isLiked = false,
                            isDisliked = false,
                        )
                    }
                    PlaybackManager.clearSubtitles()
                }
            }
        }

        val lib = libraryRepository
        val auth = authRepository
        if (lib != null && auth != null) {
            viewModelScope.launch {
                PlaybackManager.nowPlaying.flatMapLatest { nowPlaying ->
                    val ownerKey = auth.currentSession()?.ownerKey
                    if (nowPlaying == null || ownerKey == null) {
                        flowOf(Pair(false, false))
                    } else {
                        combine(
                            lib.observeIsTrackLiked(ownerKey, nowPlaying.videoId),
                            lib.observeIsNotInterested(ownerKey, nowPlaying.videoId),
                        ) { liked, disliked -> liked to disliked }
                    }
                }.collect { (liked, disliked) ->
                    expandedState.update { it.copy(isLiked = liked, isDisliked = disliked) }
                }
            }
        }
    }

    private suspend fun restorePlaybackSession() {
        val store = playbackSessionStore ?: return
        val snapshot = store.load() ?: return
        val items = snapshot.items.map { it.toQueueItem() }
        if (items.isEmpty()) return
        val repeatMode = runCatching { QueueRepeatMode.valueOf(snapshot.repeatMode) }
            .getOrDefault(QueueRepeatMode.OFF)
        val originalOrder = snapshot.originalOrder?.map { it.toQueueItem() }
        PlayQueueRepository.restore(
            items = items,
            currentIndex = snapshot.currentIndex,
            repeatMode = repeatMode,
            shuffleEnabled = snapshot.shuffleEnabled,
            sourcePlaylistId = snapshot.sourcePlaylistId,
            originalOrder = originalOrder,
        )
        val current = PlayQueueRepository.state.value.currentItem ?: return
        restoredStartPositionMs = snapshot.positionMs.coerceAtLeast(0L)
        val durationMs = snapshot.durationMs.takeIf { it > 0L }
            ?: current.durationText?.let { parsePersistedDurationMs(it) }
            ?: 0L
        PlaybackManager.restoreNowPlaying(
            item = NowPlaying(
                videoId = current.videoId,
                title = current.title,
                channelName = current.channelName,
                streamUrl = "",
                thumbnailUrl = current.thumbnailUrl,
                itag = current.itag,
                durationMs = durationMs.takeIf { it > 0L },
                channelId = current.channelId,
            ),
            positionMs = restoredStartPositionMs,
            durationMs = durationMs,
        )
        PlaybackManager.syncRepeatMode()
        showMiniPlayer.value = true
        Log.d(TAG, "Restored playback session videoId=${current.videoId} items=${items.size}")
    }

    private suspend fun persistPlaybackSession(
        queue: PlayQueueState,
        nowPlaying: NowPlaying?,
        positionMs: Long,
        durationMs: Long,
    ) {
        val store = playbackSessionStore ?: return
        if (queue.items.isEmpty() || nowPlaying == null) {
            store.clear()
            return
        }
        store.save(
            PlaybackSessionSnapshot(
                items = queue.items.map { PersistedQueueItem.from(it) },
                currentIndex = queue.currentIndex.coerceIn(0, queue.items.lastIndex),
                repeatMode = queue.repeatMode.name,
                shuffleEnabled = queue.shuffleEnabled,
                sourcePlaylistId = queue.sourcePlaylistId,
                originalOrder = PlayQueueRepository.snapshotOriginalOrder()
                    ?.map { PersistedQueueItem.from(it) },
                positionMs = positionMs.coerceAtLeast(0L),
                durationMs = durationMs.coerceAtLeast(0L),
            ),
        )
    }

    private fun parsePersistedDurationMs(text: String): Long? {
        val parts = text.trim().split(':')
        if (parts.isEmpty() || parts.any { it.toLongOrNull() == null }) return null
        var total = 0L
        for (part in parts) {
            total = total * 60 + (part.toLongOrNull() ?: return null)
        }
        return total * 1000L
    }

    private suspend fun loadPlaybackExtras(videoId: String) {
        when (val result = withContext(Dispatchers.IO) {
            extractionRepository.fetchVideoPlayback(videoId)
        }) {
            is ExtractionResult.Success -> applyPlaybackExtras(result.data)
            is ExtractionResult.Error -> Unit
        }
    }

    private fun applyPlaybackExtras(playback: VideoPlayback) {
        val tracks = playback.captionTracks
        val selected = captionRepository.pickDefaultTrack(tracks)
        expandedState.update {
            it.copy(
                captionTracks = tracks,
                selectedCaption = selected,
                currentFormats = playback.formats,
            )
        }
    }

    private suspend fun handlePlaybackEnded() {
        val repeatMode = PlayQueueRepository.state.value.repeatMode
        if (repeatMode == QueueRepeatMode.ONE) {
            PlaybackManager.resetPlaybackEnded()
            return
        }
        val advanced = PlayQueueRepository.advanceToNext()
        if (advanced == null) {
            showMiniPlayer.update { false }
            PlaybackManager.stop()
            PlayQueueRepository.clear()
            return
        }
        PlaybackManager.resetPlaybackEnded()
        playQueueItemInternal(advanced)
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
        viewModelScope.launch {
            val nowPlaying = PlaybackManager.nowPlaying.value ?: return@launch
            val player = PlaybackManager.getPlayer()
            val needsResolve = nowPlaying.streamUrl.isBlank() ||
                player == null ||
                player.mediaItemCount == 0 ||
                player.currentMediaItem?.mediaId != nowPlaying.videoId
            if (needsResolve && !PlaybackManager.isPlaying.value) {
                val item = PlayQueueRepository.state.value.currentItem
                    ?: QueueItem.fromNowPlaying(nowPlaying)
                val startPositionMs = restoredStartPositionMs
                restoredStartPositionMs = 0L
                playQueueItemInternal(item, startPositionMs = startPositionMs)
                return@launch
            }
            PlaybackManager.togglePlayPause()
        }
    }

    fun play(nowPlaying: NowPlaying) {
        restoredStartPositionMs = 0L
        PlaybackManager.play(nowPlaying)
    }

    fun seekTo(positionMs: Long) {
        PlaybackManager.seekTo(positionMs)
    }

    fun skipToNext() {
        viewModelScope.launch {
            val queueState = PlayQueueRepository.state.value
            val nextIndex = when {
                queueState.hasNext -> queueState.currentIndex + 1
                queueState.repeatMode == QueueRepeatMode.ALL && queueState.items.isNotEmpty() -> 0
                else -> return@launch
            }
            val nextItem = queueState.items.getOrNull(nextIndex) ?: return@launch
            PlayQueueRepository.setCurrentIndex(nextIndex)
            playQueueItemInternal(nextItem)
        }
    }

    fun skipToPrevious() {
        viewModelScope.launch {
            val previous = PlayQueueRepository.skipToPrevious() ?: return@launch
            playQueueItemInternal(previous)
        }
    }

    fun playQueueItem(item: QueueItem) {
        viewModelScope.launch {
            PlayQueueRepository.setCurrentIndex(
                PlayQueueRepository.state.value.items.indexOfFirst { it.videoId == item.videoId }
                    .coerceAtLeast(0),
            )
            playQueueItemInternal(item)
        }
    }

    private suspend fun playQueueItemInternal(
        item: QueueItem,
        startPositionMs: Long = 0L,
    ) {
        val streamUrl = item.streamUrl
        if (!streamUrl.isNullOrBlank()) {
            PlaybackManager.play(item.toNowPlaying(streamUrl), startPositionMs)
            PlaybackManager.syncRepeatMode()
            return
        }
        val localPath = appContext?.let { ctx ->
            withContext(Dispatchers.IO) {
                com.ytlite.player.download.DownloadRepository.getInstance(ctx)
                    .findLocalPath(item.videoId)
            }
        }
        if (!localPath.isNullOrBlank()) {
            val localUri = android.net.Uri.fromFile(java.io.File(localPath)).toString()
            PlaybackManager.play(item.toNowPlaying(localUri), startPositionMs)
            PlaybackManager.syncRepeatMode()
            return
        }
        when (val result = withContext(Dispatchers.IO) {
            extractionRepository.fetchVideoPlayback(item.videoId)
        }) {
            is ExtractionResult.Success -> {
                val format = selectFormat(result.data)
                if (format == null) {
                    Log.w(TAG, "No format for queue item ${item.videoId}")
                    handlePlaybackEnded()
                    return
                }
                applyPlaybackExtras(result.data)
                PlayQueueRepository.updateStreamUrl(item.videoId, format.url, format.itag)
                val durationMs = result.data.durationSeconds.takeIf { it > 0L }?.times(1000L)
                    ?: item.toNowPlaying(format.url).durationMs
                PlaybackManager.play(
                    item.toNowPlaying(format.url).copy(
                        itag = format.itag,
                        durationMs = durationMs,
                    ),
                    startPositionMs = startPositionMs,
                )
                PlaybackManager.syncRepeatMode()
            }
            is ExtractionResult.Error -> {
                Log.w(TAG, "Failed to resolve queue item ${item.videoId}: ${result.message}")
                handlePlaybackEnded()
            }
        }
    }

    fun reorderQueue(fromIndex: Int, toIndex: Int) {
        PlayQueueRepository.moveItem(fromIndex, toIndex)
        PlaybackManager.syncQueueOrder(PlayQueueRepository.state.value.items)
    }

    fun cycleRepeatMode() {
        val mode = PlayQueueRepository.cycleRepeatMode()
        PlaybackManager.setRepeatMode(mode)
    }

    fun toggleShuffle() {
        PlayQueueRepository.toggleShuffle()
    }

    fun setUpNextPlaybackMode(mode: UpNextPlaybackMode) {
        PlayQueueRepository.applyUpNextPlaybackMode(mode)
        PlaybackManager.syncRepeatMode()
    }

    fun removeFromQueue(videoId: String) {
        val wasCurrent = PlaybackManager.nowPlaying.value?.videoId == videoId
        PlayQueueRepository.removeItem(videoId)
        if (wasCurrent) {
            val next = PlayQueueRepository.state.value.currentItem
            if (next != null) {
                viewModelScope.launch { playQueueItemInternal(next) }
            } else {
                PlaybackManager.stop()
            }
        }
    }

    fun shufflePlayPlaylist(items: List<QueueItem>, sourcePlaylistId: String? = null) {
        if (items.isEmpty()) return
        viewModelScope.launch {
            PlayQueueRepository.setQueue(items, startIndex = 0, sourcePlaylistId = sourcePlaylistId)
            if (!PlayQueueRepository.state.value.shuffleEnabled) {
                PlayQueueRepository.toggleShuffle()
            }
            val first = PlayQueueRepository.state.value.currentItem ?: return@launch
            playQueueItemInternal(first)
            PlaybackNavigation.requestOpenPlayer(first.videoId)
            showMiniPlayer.update { true }
        }
    }

    fun playPlaylist(
        items: List<QueueItem>,
        startIndex: Int = 0,
        sourcePlaylistId: String?,
        openPlayer: Boolean = true,
    ) {
        if (items.isEmpty()) return
        val safeIndex = startIndex.coerceIn(0, items.lastIndex)
        val start = items[safeIndex]
        viewModelScope.launch {
            PlayQueueRepository.setQueue(
                items = items,
                startIndex = safeIndex,
                sourcePlaylistId = sourcePlaylistId,
            )
            if (openPlayer) {
                PlayerLaunchPreview.set(start.toVideoItem())
            }
            if (PlaybackManager.handleSameTrackClick(start.videoId)) {
                if (openPlayer) {
                    PlaybackNavigation.requestOpenPlayer(start.videoId)
                }
                showMiniPlayer.update { true }
                return@launch
            }
            val current = PlayQueueRepository.state.value.currentItem ?: return@launch
            playQueueItemInternal(current)
            if (openPlayer) {
                PlaybackNavigation.requestOpenPlayer(current.videoId)
            }
            showMiniPlayer.update { true }
        }
    }

    fun toggleLike(application: Application) {
        val nowPlaying = PlaybackManager.nowPlaying.value ?: return
        val lib = libraryRepository ?: LibraryRepositoryHolder.get(application)
        val auth = authRepository ?: com.ytlite.player.data.auth.AuthRepository.getInstance(application)
        viewModelScope.launch {
            val ownerKey = auth.currentSession()?.ownerKey ?: run {
                expandedState.update { it.copy(pendingSnackbar = "sign_in_required") }
                return@launch
            }
            val video = com.ytlite.player.data.model.LibraryVideo(
                videoId = nowPlaying.videoId,
                title = nowPlaying.title,
                channelName = nowPlaying.channelName,
                thumbnailUrl = nowPlaying.thumbnailUrl,
            )
            if (expandedState.value.isLiked) {
                lib.removeTrackFromFavorites(ownerKey, nowPlaying.videoId)
            } else {
                lib.addTrackToFavorites(ownerKey, video)
                if (expandedState.value.isDisliked) {
                    lib.removeNotInterested(ownerKey, nowPlaying.videoId)
                }
            }
        }
    }

    fun toggleDislike(application: Application) {
        val nowPlaying = PlaybackManager.nowPlaying.value ?: return
        val lib = libraryRepository ?: LibraryRepositoryHolder.get(application)
        val auth = authRepository ?: com.ytlite.player.data.auth.AuthRepository.getInstance(application)
        viewModelScope.launch {
            val ownerKey = auth.currentSession()?.ownerKey ?: run {
                expandedState.update { it.copy(pendingSnackbar = "sign_in_required") }
                return@launch
            }
            if (expandedState.value.isDisliked) {
                lib.removeNotInterested(ownerKey, nowPlaying.videoId)
            } else {
                lib.addNotInterested(ownerKey, nowPlaying.videoId)
                if (expandedState.value.isLiked) {
                    lib.removeTrackFromFavorites(ownerKey, nowPlaying.videoId)
                }
            }
        }
    }

    fun showSettingsSheet(show: Boolean) {
        expandedState.update { it.copy(showSettingsSheet = show) }
    }

    fun showCaptionSheet(show: Boolean) {
        expandedState.update { it.copy(showCaptionSheet = show) }
    }

    fun clearSnackbar() {
        expandedState.update { it.copy(pendingSnackbar = null) }
    }

    fun toggleSubtitles(application: Application) {
        val tracks = expandedState.value.captionTracks
        if (tracks.isEmpty()) {
            expandedState.update { it.copy(pendingSnackbar = "no_captions") }
            return
        }
        if (tracks.size > 1 && !expandedState.value.subtitlesEnabled) {
            showCaptionSheet(true)
            return
        }
        val enabled = !expandedState.value.subtitlesEnabled
        if (!enabled) {
            expandedState.update { it.copy(subtitlesEnabled = false) }
            PlaybackManager.setSubtitles(enabled = false)
            return
        }
        val track = expandedState.value.selectedCaption ?: tracks.first()
        applySubtitleTrack(application, track, enabled = true)
    }

    fun selectCaptionTrack(application: Application, track: CaptionTrack) {
        applySubtitleTrack(application, track, enabled = true)
        showCaptionSheet(false)
    }

    private fun applySubtitleTrack(application: Application, track: CaptionTrack, enabled: Boolean) {
        viewModelScope.launch {
            val vtt = withContext(Dispatchers.IO) { captionRepository.fetchVtt(track) }
            if (vtt.isNullOrBlank()) {
                expandedState.update { it.copy(pendingSnackbar = "caption_load_failed") }
                return@launch
            }
            val file = File(application.cacheDir, "caption_${track.languageCode}.vtt")
            withContext(Dispatchers.IO) { file.writeText(vtt) }
            expandedState.update {
                it.copy(
                    selectedCaption = track,
                    subtitlesEnabled = enabled,
                )
            }
            PlaybackManager.setSubtitles(
                enabled = enabled,
                uri = file.toURI().toString(),
                mimeType = "text/vtt",
            )
        }
    }

    fun setPlaybackSpeed(speed: Float) {
        viewModelScope.launch {
            playbackPreferences?.setPlaybackSpeed(speed)
            PlaybackManager.setPlaybackSpeed(speed)
            expandedState.update { it.copy(playbackSpeed = speed) }
        }
    }

    fun selectQualityFormat(format: StreamFormat) {
        viewModelScope.launch {
            playbackPreferences?.setPreferredItag(format.itag)
            expandedState.update { it.copy(preferredItag = format.itag) }
            val nowPlaying = PlaybackManager.nowPlaying.value ?: return@launch
            PlayQueueRepository.updateStreamUrl(nowPlaying.videoId, format.url)
            PlaybackManager.swapStreamUrl(nowPlaying.copy(streamUrl = format.url))
        }
    }

    private fun selectFormat(playback: VideoPlayback): StreamFormat? {
        val preferredItag = expandedState.value.preferredItag
        if (preferredItag != null) {
            PlaybackFormatSelector.selectByItag(playback.formats, preferredItag)?.let { return it }
        }
        return PlaybackFormatSelector.selectVideoFormat(playback.formats)
    }

    companion object {
        private const val TAG = "GlobalPlaybackVM"

        fun factory(application: Application): androidx.lifecycle.ViewModelProvider.Factory =
            viewModelFactory {
                initializer {
                    ExtractionRepository.init(application)
                    GlobalPlaybackViewModel(
                        playbackPreferences = PlaybackPreferences.getInstance(application),
                        libraryRepository = com.ytlite.player.data.repository.LibraryRepository.getInstance(application),
                        authRepository = com.ytlite.player.data.auth.AuthRepository.getInstance(application),
                        playbackSessionStore = PlaybackSessionStore.getInstance(application),
                        appContext = application.applicationContext,
                    )
                }
            }
    }
}

private object LibraryRepositoryHolder {
    fun get(application: Application) =
        com.ytlite.player.data.repository.LibraryRepository.getInstance(application)
}
