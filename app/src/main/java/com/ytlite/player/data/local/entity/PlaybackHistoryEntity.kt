package com.ytlite.player.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "playback_history",
    indices = [Index(value = ["ownerKey", "playedAt"])],
)
data class PlaybackHistoryEntity(
    @PrimaryKey val historyId: String,
    val ownerKey: String,
    val trackId: String,
    val playedAt: Long,
    val progressMs: Long = 0L,
    val isSynced: Boolean = false,
)
