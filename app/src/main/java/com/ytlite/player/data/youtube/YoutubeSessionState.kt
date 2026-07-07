package com.ytlite.player.data.youtube

sealed interface YoutubeSessionState {
    data object Disconnected : YoutubeSessionState
    /** Waiting for the user to complete Google login in the visible WebView sheet. */
    data object AwaitingInteractiveLogin : YoutubeSessionState
    data object Connecting : YoutubeSessionState
    data object Ready : YoutubeSessionState
    data class Error(val message: String) : YoutubeSessionState
}
