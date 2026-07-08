package com.ytlite.player.data.local.entity

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "search_recent_clicks")
data class SearchRecentClickEntity(
    @PrimaryKey val targetId: String,
    val type: String,
    val title: String,
    val subtitle: String = "",
    val thumbnailUrl: String = "",
    val clickedAt: Long = System.currentTimeMillis(),
)
