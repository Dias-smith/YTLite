package com.ytlite.player.data.local.entity

import androidx.room.Entity
import androidx.room.Index

@Entity(
    tableName = "playlist_display_order",
    primaryKeys = ["ownerKey", "playlistKey"],
    indices = [Index(value = ["ownerKey", "pinGroup", "position"])],
)
data class PlaylistDisplayOrderEntity(
    val ownerKey: String,
    val playlistKey: String,
    val pinGroup: Boolean,
    val position: Int,
)
