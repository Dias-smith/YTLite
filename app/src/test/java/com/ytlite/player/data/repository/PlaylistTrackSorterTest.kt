package com.ytlite.player.data.repository

import com.ytlite.player.data.local.model.PlaylistTrackDetailRow
import com.ytlite.player.data.model.PlaylistTrackSort
import org.junit.Assert.assertEquals
import org.junit.Test

class PlaylistTrackSorterTest {

    @Test
    fun sort_manual_usesPosition() {
        val tracks = listOf(
            track("b", title = "B", position = 1, addedAt = 10),
            track("a", title = "A", position = 0, addedAt = 20),
            track("c", title = "C", position = 2, addedAt = 5),
        )
        assertEquals(
            listOf("a", "b", "c"),
            PlaylistTrackSorter.sort(tracks, PlaylistTrackSort.MANUAL).map { it.trackId },
        )
    }

    @Test
    fun sort_recentlyAdded_usesAddedAtDescending() {
        val tracks = listOf(
            track("old", title = "Old", position = 0, addedAt = 10),
            track("new", title = "New", position = 1, addedAt = 30),
            track("mid", title = "Mid", position = 2, addedAt = 20),
        )
        assertEquals(
            listOf("new", "mid", "old"),
            PlaylistTrackSorter.sort(tracks, PlaylistTrackSort.RECENTLY_ADDED).map { it.trackId },
        )
    }

    @Test
    fun sort_title_isCaseInsensitive() {
        val tracks = listOf(
            track("z", title = "zeta", position = 0, addedAt = 1),
            track("a", title = "Alpha", position = 1, addedAt = 2),
            track("b", title = "beta", position = 2, addedAt = 3),
        )
        assertEquals(
            listOf("a", "b", "z"),
            PlaylistTrackSorter.sort(tracks, PlaylistTrackSort.TITLE).map { it.trackId },
        )
    }

    private fun track(
        id: String,
        title: String,
        position: Int,
        addedAt: Long,
    ) = PlaylistTrackDetailRow(
        trackId = id,
        title = title,
        primaryArtistName = null,
        primaryArtistId = null,
        thumbnailUrl = "",
        album = null,
        year = null,
        durationSeconds = 0,
        durationText = null,
        position = position,
        addedAt = addedAt,
    )
}
