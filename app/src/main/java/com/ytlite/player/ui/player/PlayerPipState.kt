package com.ytlite.player.ui.player

import android.graphics.Rect
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

object PlayerPipState {

    private val _isInPictureInPictureMode = MutableStateFlow(false)
    val isInPictureInPictureMode: StateFlow<Boolean> = _isInPictureInPictureMode.asStateFlow()

    @Volatile
    var sourceRectHint: Rect? = null

    @Volatile
    private var pendingEnterAfterFullscreenExit: Boolean = false

    fun setInPictureInPictureMode(inPip: Boolean) {
        _isInPictureInPictureMode.value = inPip
    }

    fun requestEnterPictureInPictureAfterFullscreenExit() {
        pendingEnterAfterFullscreenExit = true
    }

    fun consumePendingEnterPictureInPicture(): Boolean {
        if (!pendingEnterAfterFullscreenExit) return false
        pendingEnterAfterFullscreenExit = false
        return true
    }
}
