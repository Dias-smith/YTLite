package com.ytlite.player.data.local.model

data class LibrarySongRow(
    val trackId: String,
    val title: String,
    val primaryArtistName: String?,
    val primaryArtistId: String?,
    val thumbnailUrl: String,
    val album: String?,
    val year: String?,
    val lastActivityAt: Long,
    val savedAt: Long,
)
