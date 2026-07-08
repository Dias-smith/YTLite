package com.ytlite.player.data.auth

import androidx.compose.runtime.Immutable

@Immutable
sealed interface UserSession {
    val ownerKey: String

    @Immutable
    data class Guest(
        val guestId: String,
        val displayName: String = "",
        val handle: String = "",
    ) : UserSession {
        override val ownerKey: String = "guest:$guestId"
    }

    @Immutable
    data class Authenticated(
        val profile: UserProfile,
    ) : UserSession {
        override val ownerKey: String = "user:${profile.userId}"
    }
}
