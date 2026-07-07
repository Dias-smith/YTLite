package com.ytlite.player.data.youtube

sealed interface YoutubeSessionState {
    data object Disconnected : YoutubeSessionState
    data object Connecting : YoutubeSessionState
    data object Ready : YoutubeSessionState
    data class Error(val message: String) : YoutubeSessionState
}
