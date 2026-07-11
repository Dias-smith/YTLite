package com.ytlite.player.data.local.model

data class LibraryVideoRow(
    val trackId: String,
    val title: String,
    val primaryArtistName: String?,
    val primaryArtistId: String?,
    val thumbnailUrl: String,
    val album: String?,
    val year: String?,
    val durationText: String?,
    val viewCountText: String?,
    val publishedText: String?,
    val lastPlayedAt: Long,
    val progressMs: Long,
)
