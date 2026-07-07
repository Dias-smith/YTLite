package com.ytlite.player.data.model

import androidx.compose.runtime.Immutable

@Immutable
data class SubscriptionChannel(
    val channelId: String,
    val title: String,
    val handle: String?,
    val avatarUrl: String,
    val subscriberCountText: String?,
    val description: String?,
)

data class ChannelPage(
    val channels: List<SubscriptionChannel>,
    val continuation: String?,
)
