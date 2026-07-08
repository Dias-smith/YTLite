package com.ytlite.player.data.model

import androidx.compose.runtime.Immutable

@Immutable
sealed interface LibraryItem {
    val id: String
    val title: String
    val subtitle: String
    val coverUrl: String?
    val source: DataSource
    val sortKeyActivity: Long
    val sortKeySaved: Long

    @Immutable
    data class Playlist(
        override val id: String,
        override val title: String,
        override val subtitle: String,
        override val coverUrl: String?,
        override val source: DataSource,
        override val sortKeyActivity: Long,
        override val sortKeySaved: Long,
        val systemType: String? = null,
        val playlistId: String = id,
    ) : LibraryItem

    @Immutable
    data class Song(
        override val id: String,
        override val title: String,
        override val subtitle: String,
        override val coverUrl: String?,
        override val source: DataSource,
        override val sortKeyActivity: Long,
        override val sortKeySaved: Long,
        val videoId: String = id,
        val channelId: String? = null,
    ) : LibraryItem

    @Immutable
    data class Artist(
        override val id: String,
        override val title: String,
        override val subtitle: String,
        override val coverUrl: String?,
        override val source: DataSource,
        override val sortKeyActivity: Long,
        override val sortKeySaved: Long,
        val artistId: String = id,
    ) : LibraryItem
}
