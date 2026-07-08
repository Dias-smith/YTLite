package com.ytlite.player.data.repository

import com.ytlite.player.data.auth.UserSession
import com.ytlite.player.data.local.entity.ArtistEntity
import com.ytlite.player.data.local.entity.PlaylistEntity
import com.ytlite.player.data.local.entity.PlaylistSystemType
import com.ytlite.player.data.local.model.LibrarySongRow
import com.ytlite.player.data.model.DataSource
import com.ytlite.player.data.model.LibraryFilterChip
import com.ytlite.player.data.model.LibraryItem
import com.ytlite.player.data.model.LibrarySort
import com.ytlite.player.data.model.LibraryVideo

internal object LibraryItemMapper {

    fun playlistItem(playlist: PlaylistEntity, subtitle: String): LibraryItem.Playlist =
        LibraryItem.Playlist(
            id = playlist.playlistId,
            playlistId = playlist.playlistId,
            title = playlist.name,
            subtitle = subtitle,
            coverUrl = playlist.coverUrlOrPath,
            source = playlist.dataSource,
            sortKeyActivity = playlist.updatedAt,
            sortKeySaved = playlist.updatedAt,
            systemType = playlist.systemType,
        )

    fun songItem(row: LibrarySongRow): LibraryItem.Song =
        LibraryItem.Song(
            id = row.trackId,
            videoId = row.trackId,
            title = row.title,
            subtitle = row.primaryArtistName.orEmpty(),
            coverUrl = row.thumbnailUrl.takeIf { it.isNotBlank() },
            source = DataSource.LOCAL,
            sortKeyActivity = row.lastActivityAt,
            sortKeySaved = row.savedAt,
            channelId = row.primaryArtistId,
        )

    fun songFromVideo(video: LibraryVideo): LibraryItem.Song =
        LibraryItem.Song(
            id = video.videoId,
            videoId = video.videoId,
            title = video.title,
            subtitle = video.channelName,
            coverUrl = video.thumbnailUrl,
            source = DataSource.LOCAL,
            sortKeyActivity = video.watchedAt,
            sortKeySaved = video.watchedAt,
            channelId = video.channelId,
        )

    fun artistItem(artist: ArtistEntity): LibraryItem.Artist =
        LibraryItem.Artist(
            id = artist.artistId,
            artistId = artist.artistId,
            title = artist.name,
            subtitle = artist.subscriberCountText.orEmpty(),
            coverUrl = artist.avatarUrl,
            source = DataSource.LOCAL,
            sortKeyActivity = 0L,
            sortKeySaved = 0L,
        )

    fun mergeLocalMixed(
        playlists: List<LibraryItem.Playlist>,
        songs: List<LibraryItem.Song>,
        artists: List<LibraryItem.Artist>,
        sort: LibrarySort,
    ): List<LibraryItem> {
        val combined = buildList {
            addAll(playlists)
            addAll(songs)
            addAll(artists)
        }
        return sortItems(combined, sort)
    }

    fun sortItems(items: List<LibraryItem>, sort: LibrarySort): List<LibraryItem> =
        when (sort) {
            LibrarySort.RECENT_ACTIVITY -> items.sortedByDescending { it.sortKeyActivity }
            LibrarySort.RECENTLY_SAVED -> items.sortedByDescending { it.sortKeySaved }
        }

    fun visibleChips(session: UserSession): List<LibraryFilterChip> =
        buildList {
            add(LibraryFilterChip.PLAYLISTS)
            add(LibraryFilterChip.SONGS)
            add(LibraryFilterChip.ARTISTS)
            add(LibraryFilterChip.DOWNLOADS)
            if (session is UserSession.Authenticated) {
                add(LibraryFilterChip.YOUTUBE)
            }
        }

    fun playlistSubtitle(playlist: PlaylistEntity): String = when {
        playlist.systemType == PlaylistSystemType.FAVORITES -> "System · Liked"
        playlist.systemType == PlaylistSystemType.WATCH_LATER -> "System · Watch later"
        playlist.isYoutube() -> "YouTube · Read-only"
        else -> "Local · Playlist"
    }
}
