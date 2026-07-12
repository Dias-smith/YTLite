package com.ytlite.player.data.repository

import com.ytlite.player.data.local.model.PlaylistTrackDetailRow
import com.ytlite.player.data.model.PlaylistTrackSort

object PlaylistTrackSorter {
    fun sort(
        tracks: List<PlaylistTrackDetailRow>,
        sort: PlaylistTrackSort,
    ): List<PlaylistTrackDetailRow> = when (sort) {
        PlaylistTrackSort.MANUAL -> tracks.sortedBy { it.position }
        PlaylistTrackSort.RECENTLY_ADDED -> tracks.sortedByDescending { it.addedAt }
        PlaylistTrackSort.TITLE -> tracks.sortedBy { it.title.lowercase() }
    }
}
