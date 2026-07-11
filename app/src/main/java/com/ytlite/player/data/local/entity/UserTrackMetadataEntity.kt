package com.ytlite.player.data.local.entity

import androidx.room.Entity
import androidx.room.Index

@Entity(
    tableName = "user_track_metadata",
    primaryKeys = ["ownerKey", "trackId"],
    indices = [Index("ownerKey"), Index("trackId")],
)
data class UserTrackMetadataEntity(
    val ownerKey: String,
    val trackId: String,
    val customTitle: String? = null,
    val customArtistName: String? = null,
    val customThumbnailUrl: String? = null,
    val customAlbum: String? = null,
    val customYear: String? = null,
    val updatedAt: Long,
    val isSynced: Boolean = false,
)
