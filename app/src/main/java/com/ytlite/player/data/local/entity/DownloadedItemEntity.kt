package com.ytlite.player.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "downloaded_items",
    indices = [
        Index(value = ["videoId", "itag"], unique = true),
        Index(value = ["completedAt"]),
    ],
)
data class DownloadedItemEntity(
    @PrimaryKey val id: String,
    val videoId: String,
    val title: String,
    val channelName: String,
    val thumbnailUrl: String?,
    val itag: Int,
    val mimeType: String,
    val filePath: String,
    val contentLength: Long,
    val durationSeconds: Long = 0L,
    val completedAt: Long,
)
