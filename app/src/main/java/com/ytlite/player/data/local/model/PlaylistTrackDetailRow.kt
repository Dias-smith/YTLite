package com.ytlite.player.data.local.model

data class PlaylistTrackDetailRow(
    val trackId: String,
    val title: String,
    val primaryArtistName: String?,
    val primaryArtistId: String?,
    val thumbnailUrl: String,
    val album: String?,
    val year: String?,
    val durationSeconds: Int,
    val durationText: String?,
    val position: Int,
    val addedAt: Long,
)
