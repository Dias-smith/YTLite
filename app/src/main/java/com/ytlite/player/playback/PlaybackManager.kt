package com.ytlite.player.playback

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaController
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.MoreExecutors
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

@UnstableApi
object PlaybackManager {

    private const val TAG = "PlaybackManager"

    private val _nowPlaying = MutableStateFlow<NowPlaying?>(null)
    val nowPlaying: StateFlow<NowPlaying?> = _nowPlaying.asStateFlow()

    private val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying.asStateFlow()

    private val _positionMs = MutableStateFlow(0L)
    val positionMs: StateFlow<Long> = _positionMs.asStateFlow()

    private val _durationMs = MutableStateFlow(0L)
    val durationMs: StateFlow<Long> = _durationMs.asStateFlow()

    private val _playbackEnded = MutableStateFlow(false)
    val playbackEnded: StateFlow<Boolean> = _playbackEnded.asStateFlow()

    private val _playbackError = MutableStateFlow<String?>(null)
    val playbackError: StateFlow<String?> = _playbackError.asStateFlow()

    private val _playerState = MutableStateFlow<Player?>(null)
    val playerState: StateFlow<Player?> = _playerState.asStateFlow()

    private var appContext: Context? = null
    private var controllerFuture: ListenableFuture<MediaController>? = null
    private var controller: MediaController? = null
    private var servicePlayer: ExoPlayer? = null
    private var playerListener: Player.Listener? = null
    private var pendingPlay: NowPlaying? = null
    private var pendingQueue: List<NowPlaying>? = null
    private var pendingQueueIndex: Int = 0
    private val mainHandler = Handler(Looper.getMainLooper())

    private inline fun runOnMainThread(crossinline block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
        } else {
            mainHandler.post { block() }
        }
    }

    fun init(context: Context) {
        appContext = context.applicationContext
    }

    fun onServiceCreated(player: ExoPlayer, session: MediaSession) {
        Log.d(TAG, "Service player ready")
        servicePlayer = player
        _playerState.value = player
        attachPlayerListener(player)
        syncFromPlayer(player)
        runOnMainThread { flushPendingPlay() }
    }

    fun onServiceDestroyed() {
        Log.d(TAG, "Service destroyed")
        detachPlayerListener()
        servicePlayer = null
        controller?.release()
        controller = null
        controllerFuture = null
        _playerState.value = null
    }

    fun ensureConnected() {
        val context = appContext ?: return
        if (controller != null || controllerFuture != null) return

        Log.d(TAG, "Connecting MediaController")
        val intent = Intent(context, PlaybackService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }

        val token = SessionToken(context, ComponentName(context, PlaybackService::class.java))
        val future = MediaController.Builder(context, token).buildAsync()
        controllerFuture = future
        future.addListener(
            {
                runOnMainThread {
                    try {
                        val mediaController = future.get()
                        controller = mediaController
                        _playerState.value = mediaController
                        attachPlayerListener(mediaController)
                        syncFromPlayer(mediaController)
                        Log.d(TAG, "MediaController connected")
                        flushPendingPlay()
                    } catch (error: Exception) {
                        Log.e(TAG, "MediaController connection failed", error)
                        controllerFuture = null
                    }
                }
            },
            MoreExecutors.directExecutor(),
        )
    }

    fun getPlayer(): Player? = controller ?: servicePlayer

    fun play(item: NowPlaying) {
        runOnMainThread { requestPlay(item) }
    }

    fun playQueue(items: List<NowPlaying>, startIndex: Int = 0) {
        runOnMainThread {
            if (items.isEmpty()) return@runOnMainThread
            val safeIndex = startIndex.coerceIn(0, items.lastIndex)
            ensureConnected()
            val activePlayer = getPlayer()
            if (activePlayer == null) {
                pendingQueue = items
                pendingQueueIndex = safeIndex
                pendingPlay = items[safeIndex]
                return@runOnMainThread
            }
            playQueueOnPlayer(activePlayer, items, safeIndex)
        }
    }

    fun skipToQueueIndex(index: Int) {
        runOnMainThread {
            val queueState = PlayQueueRepository.state.value
            val item = queueState.items.getOrNull(index) ?: return@runOnMainThread
            val streamUrl = item.streamUrl ?: return@runOnMainThread
            PlayQueueRepository.setCurrentIndex(index)
            play(item.toNowPlaying(streamUrl))
        }
    }

    fun skipToNextInQueue(): Boolean {
        val next = PlayQueueRepository.advanceToNext() ?: return false
        val streamUrl = next.streamUrl ?: return true
        play(next.toNowPlaying(streamUrl))
        return true
    }

    fun skipToPreviousInQueue(): Boolean {
        val previous = PlayQueueRepository.skipToPrevious() ?: return false
        val streamUrl = previous.streamUrl ?: return true
        play(previous.toNowPlaying(streamUrl))
        return true
    }

    fun syncQueueOrder(items: List<QueueItem>) {
        runOnMainThread {
            val activePlayer = getPlayer() ?: return@runOnMainThread
            val playable = items.mapNotNull { item ->
                val url = item.streamUrl ?: return@mapNotNull null
                item.toNowPlaying(url).toMediaItem()
            }
            if (playable.isEmpty()) return@runOnMainThread
            val currentId = _nowPlaying.value?.videoId
            val currentIndex = items.indexOfFirst { it.videoId == currentId }.coerceAtLeast(0)
            activePlayer.setMediaItems(playable, currentIndex.coerceAtMost(playable.lastIndex), 0L)
            activePlayer.prepare()
        }
    }

    fun resetPlaybackEnded() {
        _playbackEnded.value = false
    }

    private fun requestPlay(item: NowPlaying) {
        ensureConnected()
        val activePlayer = getPlayer()
        if (activePlayer == null) {
            Log.w(TAG, "Player not ready, queueing videoId=${item.videoId}")
            pendingPlay = item
            return
        }
        playOnPlayer(activePlayer, item)
    }

    private fun flushPendingPlay() {
        val queue = pendingQueue
        if (queue != null) {
            val activePlayer = getPlayer()
            if (activePlayer == null) return
            pendingQueue = null
            playQueueOnPlayer(activePlayer, queue, pendingQueueIndex)
            pendingPlay = null
            return
        }
        val pending = pendingPlay ?: return
        val activePlayer = getPlayer()
        if (activePlayer == null) {
            Log.w(TAG, "flushPendingPlay: player still null for videoId=${pending.videoId}")
            return
        }
        Log.d(TAG, "Playing queued videoId=${pending.videoId}")
        pendingPlay = null
        playOnPlayer(activePlayer, pending)
    }

    private fun playQueueOnPlayer(activePlayer: Player, items: List<NowPlaying>, startIndex: Int) {
        val mediaItems = items.map { it.toMediaItem() }
        val safeIndex = startIndex.coerceIn(0, mediaItems.lastIndex)
        val current = items[safeIndex]
        _nowPlaying.value = current
        _playbackEnded.value = false
        _playbackError.value = null
        activePlayer.setMediaItems(mediaItems, safeIndex, 0L)
        activePlayer.prepare()
        activePlayer.playWhenReady = true
    }

    private fun playOnPlayer(activePlayer: Player, item: NowPlaying) {
        val urlHost = runCatching { Uri.parse(item.streamUrl).host }.getOrNull()
        Log.d(
            TAG,
            "playOnPlayer videoId=${item.videoId} player=${activePlayer::class.simpleName} " +
                "urlHost=$urlHost state=${playbackStateName(activePlayer.playbackState)}",
        )

        val current = _nowPlaying.value
        if (
            current?.videoId == item.videoId &&
            current.streamUrl == item.streamUrl &&
            activePlayer.playbackState != Player.STATE_IDLE
        ) {
            _nowPlaying.value = item
            _playbackEnded.value = false
            _playbackError.value = null
            if (!activePlayer.isPlaying) {
                activePlayer.play()
            }
            return
        }

        _nowPlaying.value = item
        _playbackEnded.value = false
        _playbackError.value = null

        val mediaItem = item.toMediaItem()
        activePlayer.setMediaItem(mediaItem)
        activePlayer.prepare()
        activePlayer.playWhenReady = true
    }

    private fun NowPlaying.toMediaItem(): MediaItem =
        MediaItem.Builder()
            .setMediaId(videoId)
            .setUri(streamUrl)
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle(title)
                    .setArtist(channelName)
                    .setArtworkUri(Uri.parse(thumbnailUrl))
                    .build(),
            )
            .build()

    fun togglePlayPause() {
        runOnMainThread {
            val activePlayer = getPlayer() ?: return@runOnMainThread
            if (activePlayer.isPlaying) {
                activePlayer.pause()
            } else {
                activePlayer.play()
            }
        }
    }

    fun pause() {
        runOnMainThread {
            getPlayer()?.pause()
        }
    }

    fun stop() {
        runOnMainThread {
            val activePlayer = getPlayer() ?: return@runOnMainThread
            activePlayer.stop()
            activePlayer.clearMediaItems()
            pendingPlay = null
            _nowPlaying.value = null
            _playbackEnded.value = false
            _playbackError.value = null
            _positionMs.value = 0L
            _durationMs.value = 0L
            _isPlaying.value = false
        }
    }

    fun clearPlaybackError() {
        _playbackError.value = null
    }

    private fun attachPlayerListener(player: Player) {
        detachPlayerListener()
        playerListener = object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                Log.d(TAG, "isPlaying=$isPlaying")
                _isPlaying.value = isPlaying
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                Log.d(TAG, "playbackState=${playbackStateName(playbackState)}")
                if (playbackState == Player.STATE_ENDED) {
                    _playbackEnded.value = true
                    _isPlaying.value = false
                } else if (playbackState == Player.STATE_READY && player.isPlaying) {
                    _playbackEnded.value = false
                }
                syncFromPlayer(player)
            }

            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                val videoId = mediaItem?.mediaId ?: return
                val queueItem = PlayQueueRepository.state.value.items.firstOrNull { it.videoId == videoId }
                if (queueItem != null) {
                    val streamUrl = queueItem.streamUrl ?: mediaItem.localConfiguration?.uri?.toString().orEmpty()
                    _nowPlaying.value = queueItem.toNowPlaying(streamUrl)
                    val index = PlayQueueRepository.state.value.items.indexOfFirst { it.videoId == videoId }
                    if (index >= 0) PlayQueueRepository.setCurrentIndex(index)
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                val message = error.message ?: error.errorCodeName
                Log.e(
                    TAG,
                    "onPlayerError code=${error.errorCode} name=${error.errorCodeName} message=$message",
                    error,
                )
                _playbackError.value = message
                _isPlaying.value = false
            }
        }
        player.addListener(playerListener!!)
    }

    private fun detachPlayerListener() {
        val listener = playerListener ?: return
        controller?.removeListener(listener)
        servicePlayer?.removeListener(listener)
        playerListener = null
    }

    fun refreshProgress() {
        getPlayer()?.let { syncFromPlayer(it) }
    }

    fun refreshProgressAndPersist() {
        refreshProgress()
        val nowPlaying = _nowPlaying.value ?: return
        onProgressTick?.invoke(nowPlaying.videoId, _positionMs.value)
    }

    var onProgressTick: ((videoId: String, progressMs: Long) -> Unit)? = null

    private fun syncFromPlayer(player: Player) {
        _isPlaying.value = player.isPlaying
        _positionMs.value = player.currentPosition.coerceAtLeast(0L)
        _durationMs.value = player.duration.coerceAtLeast(0L)
    }

    private fun playbackStateName(state: Int): String = when (state) {
        Player.STATE_IDLE -> "IDLE"
        Player.STATE_BUFFERING -> "BUFFERING"
        Player.STATE_READY -> "READY"
        Player.STATE_ENDED -> "ENDED"
        else -> "UNKNOWN($state)"
    }
}
