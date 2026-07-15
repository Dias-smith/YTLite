package com.ytlite.player.ui.library

sealed interface LibraryDestination {
    data object Home : LibraryDestination
    data object History : LibraryDestination
    data object Settings : LibraryDestination
    data object Downloads : LibraryDestination
    data class Playlist(val playlistId: String, val systemType: String? = null) : LibraryDestination
    data class AlbumTracks(val albumName: String) : LibraryDestination
}
