package com.ytlite.player.data.local.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import com.ytlite.player.data.model.DataSource

@Entity(
    tableName = "playlists",
    indices = [
        Index(value = ["ownerKey", "systemType"]),
        Index(value = ["ownerKey", "source", "updatedAt"]),
    ],
)
data class PlaylistEntity(
    @PrimaryKey val playlistId: String,
    val ownerKey: String,
    val userId: String? = null,
    val name: String,
    val coverUrlOrPath: String? = null,
    val description: String? = null,
    val systemType: String? = null,
    val source: String = DataSource.LOCAL.dbValue,
    val isSynced: Boolean = false,
    val isPinned: Boolean = false,
    val unpinnedSortAt: Long? = null,
    val pinnedAt: Long? = null,
    val updatedAt: Long = System.currentTimeMillis(),
) {
    val dataSource: DataSource get() = DataSource.fromDb(source)

    fun isYoutube(): Boolean = dataSource == DataSource.YOUTUBE

    fun isLocal(): Boolean = dataSource == DataSource.LOCAL
}
