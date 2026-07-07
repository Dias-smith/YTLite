package com.ytlite.player.data.youtube

import androidx.compose.runtime.Immutable

@Immutable
data class YoutubeLoginUiState(
    val initialUrl: String,
    val emailHint: String?,
)
