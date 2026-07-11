package com.ytlite.player.data.model

import androidx.compose.runtime.Immutable

@Immutable
sealed interface SearchResultItem {
    val id: String
    val title: String
    val subtitle: String
    val thumbnailUrl: String?

    @Immutable
    data class Video(
        override val id: String,
        val videoId: String,
        override val title: String,
        override val subtitle: String,
        override val thumbnailUrl: String?,
        val channelName: String = "",
        val channelId: String? = null,
        val viewCountText: String? = null,
    ) : SearchResultItem

    @Immutable
    data class Channel(
        override val id: String,
        val channelId: String,
        override val title: String,
        override val subtitle: String,
        override val thumbnailUrl: String?,
    ) : SearchResultItem

    @Immutable
    data class Playlist(
        override val id: String,
        val playlistId: String,
        override val title: String,
        override val subtitle: String,
        override val thumbnailUrl: String?,
        val videoCountText: String? = null,
    ) : SearchResultItem
}

@Immutable
data class SearchResultPage(
    val items: List<SearchResultItem>,
    val continuation: String? = null,
)
