package com.ytlite.player.data.local.entity

import androidx.room.Entity
import androidx.room.Index

@Entity(
    tableName = "playlist_pin_overlay",
    primaryKeys = ["playlistId", "ownerKey"],
    indices = [Index(value = ["ownerKey"])],
)
data class PlaylistPinOverlayEntity(
    val playlistId: String,
    val ownerKey: String,
    val isPinned: Boolean = false,
    val unpinnedSortAt: Long? = null,
    val pinnedAt: Long? = null,
    val updatedAt: Long = System.currentTimeMillis(),
)
