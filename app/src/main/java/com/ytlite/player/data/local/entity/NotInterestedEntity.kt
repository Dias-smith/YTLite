package com.ytlite.player.data.local.entity

import androidx.room.Entity
import androidx.room.Index

@Entity(
    tableName = "not_interested",
    primaryKeys = ["ownerKey", "videoId"],
    indices = [Index("ownerKey")],
)
data class NotInterestedEntity(
    val ownerKey: String,
    val videoId: String,
    val createdAt: Long,
)
