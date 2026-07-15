package com.ytlite.player.data.local.entity

import androidx.room.Entity
import androidx.room.Index

@Entity(
    tableName = "user_subscribed_channels",
    primaryKeys = ["ownerKey", "channelId"],
    indices = [Index("ownerKey"), Index("channelId")],
)
data class UserSubscribedChannelEntity(
    val ownerKey: String,
    val channelId: String,
    val title: String,
    val handle: String? = null,
    val avatarUrl: String? = null,
    val subscriberCountText: String? = null,
    val description: String? = null,
    val subscribedAt: Long,
    val isSynced: Boolean = false,
)
