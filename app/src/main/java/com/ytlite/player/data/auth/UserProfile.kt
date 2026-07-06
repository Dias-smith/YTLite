package com.ytlite.player.data.auth

import androidx.compose.runtime.Immutable

@Immutable
data class UserProfile(
    val userId: String,
    val displayName: String,
    val handle: String?,
    val avatarUrl: String?,
)
