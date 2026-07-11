package com.ytlite.player.data.repository

import com.ytlite.player.data.local.entity.PlaylistSystemType
import com.ytlite.player.data.model.DataSource
import com.ytlite.player.data.model.LibraryItem
import com.ytlite.player.data.model.LibrarySort
import org.junit.Assert.assertEquals
import org.junit.Test

class LibraryItemMapperTest {

    @Test
    fun orderPlaylistItems_pinsSystemPlaylistsBeforeCustomOnes() {
        val custom = playlist(
            id = "custom-1",
            title = "test",
            sortKey = 9_000L,
        )
        val watchLater = playlist(
            id = "system:watch_later",
            title = "Watch later",
            systemType = PlaylistSystemType.WATCH_LATER,
            sortKey = 1_000L,
        )
        val liked = playlist(
            id = "system:favorites",
            title = "Liked videos",
            systemType = PlaylistSystemType.FAVORITES,
            sortKey = 2_000L,
        )

        val ordered = LibraryItemMapper.orderPlaylistItems(
            items = listOf(custom, watchLater, liked),
            sort = LibrarySort.RECENT_ACTIVITY,
        )

        assertEquals(
            listOf(
                PlaylistSystemType.FAVORITES,
                PlaylistSystemType.WATCH_LATER,
                PlaylistSystemType.HISTORY,
                null,
            ),
            ordered.map { (it as LibraryItem.Playlist).systemType },
        )
        assertEquals("test", (ordered[3] as LibraryItem.Playlist).title)
    }

    @Test
    fun orderPlaylistItems_sortsCustomPlaylistsByRecentActivity() {
        val older = playlist(id = "older", title = "Older", sortKey = 100L)
        val newer = playlist(id = "newer", title = "Newer", sortKey = 200L)

        val ordered = LibraryItemMapper.orderPlaylistItems(
            items = listOf(older, newer),
            sort = LibrarySort.RECENT_ACTIVITY,
        )

        assertEquals("Newer", (ordered[3] as LibraryItem.Playlist).title)
        assertEquals("Older", (ordered[4] as LibraryItem.Playlist).title)
    }

    private fun playlist(
        id: String,
        title: String,
        systemType: String? = null,
        sortKey: Long = 0L,
    ) = LibraryItem.Playlist(
        id = id,
        playlistId = id,
        title = title,
        subtitle = "subtitle",
        coverUrl = null,
        source = DataSource.LOCAL,
        sortKeyActivity = sortKey,
        sortKeySaved = sortKey,
        systemType = systemType,
    )
}
