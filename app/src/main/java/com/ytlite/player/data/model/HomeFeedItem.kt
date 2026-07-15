package com.ytlite.player.data.model

import androidx.compose.runtime.Immutable

@Immutable
sealed interface HomeFeedItem {
    val id: String

    @Immutable
    data class Track(
        val video: VideoItem,
    ) : HomeFeedItem {
        override val id: String get() = video.videoId
    }

    @Immutable
    data class Album(
        val browseId: String,
        val playlistId: String?,
        val title: String,
        val artistName: String,
        val thumbnailUrl: String,
        val releaseType: String,
    ) : HomeFeedItem {
        override val id: String get() = browseId
    }
}

data class HomeFeedPage(
    val items: List<HomeFeedItem>,
    val continuation: String?,
)
