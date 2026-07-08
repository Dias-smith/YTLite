package com.ytlite.player.ui.library

sealed interface LibraryDestination {
    data object Home : LibraryDestination
    data object History : LibraryDestination
    data class Playlist(val playlistId: String, val systemType: String? = null) : LibraryDestination
}
