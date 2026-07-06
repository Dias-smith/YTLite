package com.ytlite.player.data.local.entity

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "artists")
data class ArtistEntity(
    @PrimaryKey val artistId: String,
    val name: String,
    val avatarUrl: String? = null,
    val bannerUrl: String? = null,
    val subscriberCount: Long? = null,
    val subscriberCountText: String? = null,
    val description: String? = null,
)
