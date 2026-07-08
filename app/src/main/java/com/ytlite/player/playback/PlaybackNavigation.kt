package com.ytlite.player.playback

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/** Routes notification / media-button taps into Compose navigation. */
object PlaybackNavigation {

    private val _openPlayerRequests = MutableSharedFlow<String>(extraBufferCapacity = 1)
    val openPlayerRequests: SharedFlow<String> = _openPlayerRequests.asSharedFlow()

    fun requestOpenPlayer(videoId: String) {
        _openPlayerRequests.tryEmit(videoId)
    }
}
