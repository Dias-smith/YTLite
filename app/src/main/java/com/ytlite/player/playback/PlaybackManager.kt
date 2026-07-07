package com.ytlite.player.playback

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
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
import kotlinx.coroutines.flow.update

@UnstableApi
object PlaybackManager {

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

    private val _playerState = MutableStateFlow<Player?>(null)
    val playerState: StateFlow<Player?> = _playerState.asStateFlow()

    private var appContext: Context? = null
    private var controllerFuture: ListenableFuture<MediaController>? = null
    private var controller: MediaController? = null
    private var servicePlayer: ExoPlayer? = null
    private var playerListener: Player.Listener? = null

    fun init(context: Context) {
        appContext = context.applicationContext
    }

    fun onServiceCreated(player: ExoPlayer, session: MediaSession) {
        servicePlayer = player
        _playerState.value = player
        attachPlayerListener(player)
        syncFromPlayer(player)
    }

    fun onServiceDestroyed() {
        detachPlayerListener()
        servicePlayer = null
        controller?.release()
        controller = null
        controllerFuture = null
        _playerState.value = null
    }

    fun ensureConnected() {
        val context = appContext ?: return
        if (controller != null) return

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
                val mediaController = future.get()
                controller = mediaController
                _playerState.value = mediaController
                attachPlayerListener(mediaController)
                syncFromPlayer(mediaController)
            },
            MoreExecutors.directExecutor(),
        )
    }

    fun getPlayer(): Player? = controller ?: servicePlayer

    fun play(item: NowPlaying) {
        ensureConnected()
        val activePlayer = getPlayer() ?: return

        val current = _nowPlaying.value
        if (
            current?.videoId == item.videoId &&
            current.streamUrl == item.streamUrl &&
            activePlayer.playbackState != Player.STATE_IDLE
        ) {
            _nowPlaying.value = item
            _playbackEnded.value = false
            if (!activePlayer.isPlaying) {
                activePlayer.play()
            }
            return
        }

        _nowPlaying.value = item
        _playbackEnded.value = false

        val mediaItem = MediaItem.Builder()
            .setMediaId(item.videoId)
            .setUri(item.streamUrl)
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setTitle(item.title)
                    .setArtist(item.channelName)
                    .setArtworkUri(Uri.parse(item.thumbnailUrl))
                    .build(),
            )
            .build()

        activePlayer.setMediaItem(mediaItem)
        activePlayer.prepare()
        activePlayer.playWhenReady = true
    }

    fun togglePlayPause() {
        val activePlayer = getPlayer() ?: return
        if (activePlayer.isPlaying) {
            activePlayer.pause()
        } else {
            activePlayer.play()
        }
    }

    fun stop() {
        val activePlayer = getPlayer() ?: return
        activePlayer.stop()
        activePlayer.clearMediaItems()
        _nowPlaying.value = null
        _playbackEnded.value = false
        _positionMs.value = 0L
        _durationMs.value = 0L
        _isPlaying.value = false
    }

    private fun attachPlayerListener(player: Player) {
        detachPlayerListener()
        playerListener = object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                _isPlaying.value = isPlaying
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                if (playbackState == Player.STATE_ENDED) {
                    _playbackEnded.value = true
                    _isPlaying.value = false
                }
                syncFromPlayer(player)
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
}
