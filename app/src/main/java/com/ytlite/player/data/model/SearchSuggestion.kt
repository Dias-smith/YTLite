package com.ytlite.player.data.model

import androidx.compose.runtime.Immutable

@Immutable
sealed interface SearchSuggestion {
    val id: String

    @Immutable
    data class Query(
        override val id: String,
        val text: String,
        val isFromHistory: Boolean,
    ) : SearchSuggestion

    @Immutable
    data class Channel(
        override val id: String,
        val channelId: String,
        val title: String,
        val subtitle: String,
        val avatarUrl: String?,
    ) : SearchSuggestion

    @Immutable
    data class Video(
        override val id: String,
        val videoId: String,
        val title: String,
        val subtitle: String,
        val thumbnailUrl: String?,
    ) : SearchSuggestion
}
