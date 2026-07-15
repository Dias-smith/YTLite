package com.ytlite.player.data.local.model

data class LibraryArtistRow(
    val artistId: String,
    val name: String,
    val avatarUrl: String?,
    val lastActivityAt: Long,
    val savedAt: Long,
)
