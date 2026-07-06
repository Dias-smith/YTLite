package com.ytlite.player.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "playlists",
    indices = [Index(value = ["ownerKey", "systemType"])],
)
data class PlaylistEntity(
    @PrimaryKey val playlistId: String,
    val ownerKey: String,
    val userId: String? = null,
    val name: String,
    val coverUrlOrPath: String? = null,
    val description: String? = null,
    val systemType: String? = null,
    val isSynced: Boolean = false,
)
