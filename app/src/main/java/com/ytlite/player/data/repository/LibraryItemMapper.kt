package com.ytlite.player.data.repository

import com.ytlite.player.data.auth.UserSession
import com.ytlite.player.data.local.entity.PlaylistEntity
import com.ytlite.player.data.local.entity.PlaylistSystemType
import com.ytlite.player.data.local.entity.UserSubscribedChannelEntity
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
            sortKeyActivity = playlist.sortKeyActivity(),
            sortKeySaved = playlist.sortKeySaved(),
            systemType = playlist.systemType,
            isPinned = playlist.isPinned,
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

    fun channelItem(entity: UserSubscribedChannelEntity): LibraryItem.Channel =
        LibraryItem.Channel(
            id = entity.channelId,
            channelId = entity.channelId,
            title = entity.title,
            subtitle = entity.subscriberCountText.orEmpty().ifBlank {
                entity.handle.orEmpty()
            },
            coverUrl = entity.avatarUrl,
            source = DataSource.LOCAL,
            sortKeyActivity = entity.subscribedAt,
            sortKeySaved = entity.subscribedAt,
            handle = entity.handle,
            description = entity.description,
        )

    /**
     * Stable key for an artist/channel catalog entry. Prefers YouTube channelId.
     */
    fun artistKey(channelId: String?, channelName: String): String {
        channelId?.takeIf { it.isNotBlank() }?.let { return it.trim() }
        return "name:${channelName.trim().lowercase()}"
    }

    fun isBrowsableChannelId(channelId: String): Boolean =
        channelId.isNotBlank() && !channelId.startsWith("name:")

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
        channels: List<LibraryItem.Channel>,
        sort: LibrarySort,
    ): List<LibraryItem> {
        val combined = buildList {
            addAll(playlists)
            addAll(songs)
            addAll(channels)
        }
        return sortItems(combined, sort)
    }

    fun sortItems(items: List<LibraryItem>, sort: LibrarySort): List<LibraryItem> =
        when (sort) {
            LibrarySort.RECENT_ACTIVITY -> items.sortedByDescending { it.sortKeyActivity }
            LibrarySort.RECENTLY_SAVED -> items.sortedByDescending { it.sortKeySaved }
            LibrarySort.CUSTOM -> items.sortedByDescending { it.sortKeyActivity }
        }

    fun orderPlaylistItems(
        items: List<LibraryItem.Playlist>,
        sort: LibrarySort,
        manualOrder: Map<String, Int> = emptyMap(),
        includeHistory: Boolean = true,
        historySubtitle: String? = null,
    ): List<LibraryItem> {
        val allItems = buildList {
            addAll(items)
            if (includeHistory && items.none { it.systemType == PlaylistSystemType.HISTORY }) {
                add(
                    historyPlaylistItem(
                        subtitle = historySubtitle
                            ?: systemPlaylistSubtitle(PlaylistSystemType.HISTORY),
                    ),
                )
            }
        }
        val pinned = sortPlaylists(allItems.filter { it.isPinned }, sort, manualOrder)
        val unpinned = sortPlaylists(allItems.filter { !it.isPinned }, sort, manualOrder)
        return pinned + unpinned
    }

    private fun sortPlaylists(
        items: List<LibraryItem.Playlist>,
        sort: LibrarySort,
        manualOrder: Map<String, Int>,
    ): List<LibraryItem.Playlist> =
        when (sort) {
            LibrarySort.CUSTOM -> items.sortedWith(
                compareBy<LibraryItem.Playlist> { manualOrder[it.id] ?: Int.MAX_VALUE }
                    .thenBy { systemPlaylistDefaultOrder(it.systemType) }
                    .thenByDescending { it.sortKeyActivity },
            )
            LibrarySort.RECENT_ACTIVITY -> items.sortedWith(
                compareBy<LibraryItem.Playlist> { systemPlaylistDefaultOrder(it.systemType) }
                    .thenByDescending { it.sortKeyActivity },
            )
            LibrarySort.RECENTLY_SAVED -> items.sortedWith(
                compareBy<LibraryItem.Playlist> { systemPlaylistDefaultOrder(it.systemType) }
                    .thenByDescending { it.sortKeySaved },
            )
        }

    /** Default order for system playlists: Liked → Watch later → History. */
    private fun systemPlaylistDefaultOrder(systemType: String?): Int = when (systemType) {
        PlaylistSystemType.FAVORITES -> 0
        PlaylistSystemType.WATCH_LATER -> 1
        PlaylistSystemType.HISTORY -> 2
        else -> Int.MAX_VALUE
    }

    fun historyPlaylistItem(subtitle: String = "System"): LibraryItem.Playlist =
        LibraryItem.Playlist(
            id = "system:history",
            playlistId = "system:history",
            title = "History",
            subtitle = subtitle,
            coverUrl = null,
            source = DataSource.LOCAL,
            sortKeyActivity = 0L,
            sortKeySaved = 0L,
            systemType = PlaylistSystemType.HISTORY,
        )

    private fun systemPlaylistTitle(systemType: String): String = when (systemType) {
        PlaylistSystemType.WATCH_LATER -> "Watch later"
        PlaylistSystemType.FAVORITES -> "Liked videos"
        PlaylistSystemType.HISTORY -> "History"
        else -> systemType
    }

    fun systemPlaylistSubtitle(systemType: String): String = "System"

    @Suppress("UNUSED_PARAMETER")
    fun visibleChips(session: UserSession): List<LibraryFilterChip> =
        listOf(
            LibraryFilterChip.PLAYLISTS,
            LibraryFilterChip.SONGS,
            LibraryFilterChip.CHANNELS,
            // Downloads uses a fixed entry card on Library home (not a filter chip).
            // Albums / YouTube chips intentionally hidden for v1.
        )

    fun playlistSubtitle(playlist: PlaylistEntity): String = when {
        playlist.systemType != null -> "System"
        playlist.isYoutube() -> "YouTube"
        else -> "Local"
    }

    fun playlistSubtitleWithCount(baseSubtitle: String, songsLabel: String): String =
        "$baseSubtitle · $songsLabel"

    fun playlistListKey(playlist: PlaylistEntity): String = playlist.listKey()

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

    fun PlaylistEntity.sortKeyActivity(): Long = effectiveSortAt()

    fun PlaylistEntity.sortKeySaved(): Long = effectiveSortAt()

    private fun PlaylistEntity.effectiveSortAt(): Long = when {
        isPinned -> pinnedAt ?: updatedAt
        else -> updatedAt
    }
}
