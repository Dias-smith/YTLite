package com.ytlite.player.data.repository

import com.ytlite.player.data.local.entity.PlaylistSystemType
import com.ytlite.player.data.model.DataSource
import com.ytlite.player.data.model.LibraryItem
import com.ytlite.player.data.model.LibrarySort
import org.junit.Assert.assertEquals
import org.junit.Test

class LibraryItemMapperTest {

    @Test
    fun orderPlaylistItems_putsPinnedPlaylistsBeforeUnpinnedOnes() {
        val unpinnedLiked = playlist(
            id = "liked",
            title = "Liked videos",
            systemType = PlaylistSystemType.FAVORITES,
            sortKey = 500L,
        )
        val pinnedCustom = playlist(
            id = "pinned",
            title = "Pinned",
            sortKey = 100L,
            isPinned = true,
        )

        val ordered = LibraryItemMapper.orderPlaylistItems(
            items = listOf(unpinnedLiked, pinnedCustom),
            sort = LibrarySort.RECENT_ACTIVITY,
        )

        assertEquals(
            listOf("Pinned", "Liked videos", "History"),
            ordered.map { (it as LibraryItem.Playlist).title },
        )
    }

    @Test
    fun orderPlaylistItems_pinsCustomPlaylistsBeforeUnpinnedCustom() {
        val unpinned = playlist(id = "unpinned", title = "Unpinned", sortKey = 300L)
        val pinned = playlist(id = "pinned", title = "Pinned", sortKey = 100L, isPinned = true)

        val ordered = LibraryItemMapper.orderPlaylistItems(
            items = listOf(unpinned, pinned),
            sort = LibrarySort.RECENT_ACTIVITY,
        )

        assertEquals(
            listOf("Pinned", "Unpinned", "History"),
            ordered.map { (it as LibraryItem.Playlist).title },
        )
    }

    @Test
    fun orderPlaylistItems_sortsWithinPinnedAndUnpinnedGroups() {
        val pinnedOlder = playlist(id = "pinned-old", title = "Pinned Old", sortKey = 100L, isPinned = true)
        val pinnedNewer = playlist(id = "pinned-new", title = "Pinned New", sortKey = 200L, isPinned = true)
        val unpinnedOlder = playlist(id = "older", title = "Older", sortKey = 100L)
        val unpinnedNewer = playlist(id = "newer", title = "Newer", sortKey = 200L)

        val ordered = LibraryItemMapper.orderPlaylistItems(
            items = listOf(pinnedOlder, unpinnedOlder, pinnedNewer, unpinnedNewer),
            sort = LibrarySort.RECENT_ACTIVITY,
        )

        assertEquals(
            listOf("Pinned New", "Pinned Old", "Newer", "Older", "History"),
            ordered.map { (it as LibraryItem.Playlist).title },
        )
    }

    @Test
    fun orderPlaylistItems_skipsHistoryWhenIncludeHistoryFalse() {
        val custom = playlist(id = "custom", title = "Custom", sortKey = 100L)

        val ordered = LibraryItemMapper.orderPlaylistItems(
            items = listOf(custom),
            sort = LibrarySort.RECENT_ACTIVITY,
            includeHistory = false,
        )

        assertEquals(listOf("Custom"), ordered.map { (it as LibraryItem.Playlist).title })
    }

    @Test
    fun orderPlaylistItems_usesPinnedAtWithinPinnedGroup() {
        val pinnedOlder = playlist(
            id = "pinned-old",
            title = "Pinned Old",
            sortKey = 100L,
            isPinned = true,
            pinnedAt = 100L,
        )
        val pinnedNewer = playlist(
            id = "pinned-new",
            title = "Pinned New",
            sortKey = 50L,
            isPinned = true,
            pinnedAt = 200L,
        )

        val ordered = LibraryItemMapper.orderPlaylistItems(
            items = listOf(pinnedOlder, pinnedNewer),
            sort = LibrarySort.RECENT_ACTIVITY,
            includeHistory = false,
        )

        assertEquals(
            listOf("Pinned New", "Pinned Old"),
            ordered.map { (it as LibraryItem.Playlist).title },
        )
    }

    @Test
    fun orderPlaylistItems_appliesCustomManualOrderWithinGroups() {
        val pinnedA = playlist(id = "pinned-a", title = "Pinned A", sortKey = 300L, isPinned = true)
        val pinnedB = playlist(id = "pinned-b", title = "Pinned B", sortKey = 100L, isPinned = true)
        val unpinnedA = playlist(id = "unpinned-a", title = "Unpinned A", sortKey = 200L)
        val unpinnedB = playlist(id = "unpinned-b", title = "Unpinned B", sortKey = 400L)

        val ordered = LibraryItemMapper.orderPlaylistItems(
            items = listOf(pinnedA, pinnedB, unpinnedA, unpinnedB),
            sort = LibrarySort.CUSTOM,
            manualOrder = mapOf(
                "pinned-a" to 1,
                "pinned-b" to 0,
                "unpinned-a" to 1,
                "unpinned-b" to 0,
            ),
            includeHistory = false,
        )

        assertEquals(
            listOf("Pinned B", "Pinned A", "Unpinned B", "Unpinned A"),
            ordered.map { (it as LibraryItem.Playlist).title },
        )
    }

    private fun playlist(
        id: String,
        title: String,
        systemType: String? = null,
        sortKey: Long = 0L,
        isPinned: Boolean = false,
        pinnedAt: Long? = null,
    ) = LibraryItem.Playlist(
        id = id,
        playlistId = id,
        title = title,
        subtitle = "subtitle",
        coverUrl = null,
        source = DataSource.LOCAL,
        sortKeyActivity = pinnedAt ?: sortKey,
        sortKeySaved = pinnedAt ?: sortKey,
        systemType = systemType,
        isPinned = isPinned,
    )
}
