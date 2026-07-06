package com.ytlite.player.data.local.entity

import androidx.room.Entity
import androidx.room.Index

@Entity(
    tableName = "playlist_track_cross_ref",
    primaryKeys = ["playlistId", "trackId"],
    indices = [Index(value = ["playlistId", "position"])],
)
data class PlaylistTrackEntity(
    val playlistId: String,
    val trackId: String,
    val position: Int = 0,
    val createdAt: Long = System.currentTimeMillis(),
    val isSynced: Boolean = false,
)
