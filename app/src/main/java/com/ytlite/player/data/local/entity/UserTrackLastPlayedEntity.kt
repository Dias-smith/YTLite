package com.ytlite.player.data.local.entity

import androidx.room.Entity
import androidx.room.Index

@Entity(
    tableName = "user_track_last_played",
    primaryKeys = ["ownerKey", "trackId"],
    indices = [Index(value = ["ownerKey", "lastPlayedAt"])],
)
data class UserTrackLastPlayedEntity(
    val ownerKey: String,
    val trackId: String,
    val lastPlayedAt: Long,
    val progressMs: Long = 0L,
    val isSynced: Boolean = false,
)
