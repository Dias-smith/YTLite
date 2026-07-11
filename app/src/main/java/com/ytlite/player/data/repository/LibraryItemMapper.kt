package com.ytlite.player.data.repository

import com.ytlite.player.data.auth.UserSession
import com.ytlite.player.data.local.entity.ArtistEntity
import com.ytlite.player.data.local.entity.PlaylistEntity
import com.ytlite.player.data.local.entity.PlaylistSystemType
import com.ytlite.player.data.local.model.LibraryAlbumRow
import com.ytlite.player.data.local.model.LibrarySongRow
import com.ytlite.player.data.model.DataSource
import com.ytlite.player.data.model.LibraryFilterChip
import com.ytlite.player.data.model.LibraryItem
import com.ytlite.player.data.model.LibrarySort
import com.ytlite.player.data.model.LibraryVideo

internal object LibraryItemMapper {

    fun playlistItem(playlist: PlaylistEntity, subtitle: String): LibraryItem.Playlist =
        LibraryItem.Playlist(
            id = playlist.listKey(),
            playlistId = playlist.playlistId,
            title = playlist.displayTitle(),
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
            subtitle = formatSongSubtitle(row.primaryArtistName, row.album, row.year),
            coverUrl = row.thumbnailUrl.takeIf { it.isNotBlank() },
            source = DataSource.LOCAL,
            sortKeyActivity = row.lastActivityAt,
            sortKeySaved = row.savedAt,
            channelId = row.primaryArtistId,
            artistName = row.primaryArtistName.orEmpty(),
            album = row.album,
            year = row.year,
        )

    fun formatSongSubtitle(
        artist: String?,
        album: String?,
        year: String?,
    ): String = listOfNotNull(
        artist?.takeIf { it.isNotBlank() },
        album?.takeIf { it.isNotBlank() },
        year?.takeIf { it.isNotBlank() },
    ).joinToString(" · ")

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
            artistName = video.channelName,
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

    fun albumItem(row: LibraryAlbumRow): LibraryItem.Album =
        LibraryItem.Album(
            id = row.albumName.lowercase(),
            albumName = row.albumName,
            title = row.albumName,
            subtitle = "Album",
            coverUrl = null,
            source = DataSource.LOCAL,
            sortKeyActivity = row.lastActivityAt,
            sortKeySaved = row.savedAt,
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

    private val pinnedSystemPlaylistTypes = listOf(
        PlaylistSystemType.FAVORITES,
        PlaylistSystemType.WATCH_LATER,
    )

    fun orderPlaylistItems(
        items: List<LibraryItem.Playlist>,
        sort: LibrarySort,
    ): List<LibraryItem> {
        val bySystemType = items
            .filter { it.systemType != null }
            .associateBy { it.systemType!! }
        val pinned = buildList {
            pinnedSystemPlaylistTypes.forEach { systemType ->
                add(bySystemType[systemType] ?: syntheticSystemPlaylist(systemType))
            }
            add(historyPlaylistItem())
        }
        val customPlaylists = items.filter { it.systemType == null }
        return pinned + sortItems(customPlaylists, sort)
    }

    fun historyPlaylistItem(): LibraryItem.Playlist = LibraryItem.Playlist(
        id = "system:history",
        playlistId = "system:history",
        title = "History",
        subtitle = systemPlaylistSubtitle(PlaylistSystemType.HISTORY),
        coverUrl = null,
        source = DataSource.LOCAL,
        sortKeyActivity = Long.MAX_VALUE,
        sortKeySaved = Long.MAX_VALUE,
        systemType = PlaylistSystemType.HISTORY,
    )

    private fun syntheticSystemPlaylist(systemType: String): LibraryItem.Playlist {
        val id = when (systemType) {
            PlaylistSystemType.FAVORITES -> "system:favorites"
            PlaylistSystemType.WATCH_LATER -> "system:watch_later"
            else -> "system:$systemType"
        }
        return LibraryItem.Playlist(
            id = id,
            playlistId = id,
            title = systemPlaylistTitle(systemType),
            subtitle = systemPlaylistSubtitle(systemType),
            coverUrl = null,
            source = DataSource.LOCAL,
            sortKeyActivity = Long.MAX_VALUE,
            sortKeySaved = Long.MAX_VALUE,
            systemType = systemType,
        )
    }

    private fun systemPlaylistTitle(systemType: String): String = when (systemType) {
        PlaylistSystemType.WATCH_LATER -> "Watch later"
        PlaylistSystemType.FAVORITES -> "Liked videos"
        PlaylistSystemType.HISTORY -> "History"
        else -> systemType
    }

    private fun systemPlaylistSubtitle(systemType: String): String = when (systemType) {
        PlaylistSystemType.FAVORITES -> "System · Liked"
        PlaylistSystemType.WATCH_LATER -> "System · Watch later"
        PlaylistSystemType.HISTORY -> "System · History"
        else -> "System · Playlist"
    }

    fun visibleChips(session: UserSession): List<LibraryFilterChip> =
        buildList {
            add(LibraryFilterChip.PLAYLISTS)
            add(LibraryFilterChip.SONGS)
            add(LibraryFilterChip.ARTISTS)
            add(LibraryFilterChip.ALBUMS)
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

    private fun PlaylistEntity.listKey(): String = when (systemType) {
        PlaylistSystemType.FAVORITES -> "system:favorites"
        PlaylistSystemType.WATCH_LATER -> "system:watch_later"
        else -> playlistId
    }

    private fun PlaylistEntity.displayTitle(): String = when (systemType) {
        PlaylistSystemType.WATCH_LATER -> "Watch later"
        PlaylistSystemType.FAVORITES -> "Liked videos"
        else -> name
    }
}
