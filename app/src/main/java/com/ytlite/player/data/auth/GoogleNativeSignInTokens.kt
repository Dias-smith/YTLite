package com.ytlite.player.data.auth

data class GoogleNativeSignInTokens(
    val idToken: String,
    val accessToken: String?,
    val nonce: String,
)
