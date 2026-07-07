package com.ytlite.player.data.auth

import androidx.compose.runtime.Immutable

@Immutable
data class OwnedYoutubeChannel(
    val channelId: String,
    val title: String,
    val handle: String?,
    val avatarUrl: String?,
    val subscriberCount: Long?,
    val hiddenSubscriberCount: Boolean = false,
)
