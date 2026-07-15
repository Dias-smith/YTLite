package com.ytlite.player.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

object DownloadTaskStatus {
    const val QUEUED = "queued"
    const val RUNNING = "running"
    const val PAUSED = "paused"
    const val FAILED = "failed"
    const val COMPLETED = "completed"
    const val CANCELLED = "cancelled"
}

@Entity(
    tableName = "download_tasks",
    indices = [
        Index(value = ["videoId", "itag"]),
        Index(value = ["status"]),
    ],
)
data class DownloadTaskEntity(
    @PrimaryKey val id: String,
    val videoId: String,
    val title: String,
    val channelName: String,
    val thumbnailUrl: String?,
    val itag: Int,
    val mimeType: String,
    val url: String,
    val filePath: String,
    val totalBytes: Long = 0L,
    val downloadedBytes: Long = 0L,
    val status: String = DownloadTaskStatus.QUEUED,
    val errorMessage: String? = null,
    val createdAt: Long,
    val updatedAt: Long,
    val etag: String? = null,
    val lastModified: String? = null,
    val durationSeconds: Long = 0L,
)
