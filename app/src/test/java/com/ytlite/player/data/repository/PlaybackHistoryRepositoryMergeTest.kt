package com.ytlite.player.data.repository

import com.ytlite.player.data.local.entity.TrackEntity
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Regression tests for [PlaybackHistoryRepository] canonical merge behavior.
 * Ensures re-depositing playback with sparse YouTube payloads does not wipe stored metadata.
 */
class PlaybackHistoryRepositoryMergeTest {

    @Test
    fun mergeCanonicalTrack_preservesExistingWhenIncomingBlank() {
        val existing = TrackEntity(
            trackId = "vid1",
            title = "Stored Title",
            durationSeconds = 240,
            thumbnailHigh = "https://stored/thumb.jpg",
            primaryArtistId = "ch1",
            primaryArtistName = "Stored Artist",
            viewCountText = "1M views",
        )

        val merged = mergeCanonicalTrack(
            existing = existing,
            trackId = "vid1",
            title = "",
            durationSeconds = 0,
            thumbnailUrl = "",
            channelId = null,
            channelName = null,
        )

        assertEquals("Stored Title", merged.title)
        assertEquals(240, merged.durationSeconds)
        assertEquals("https://stored/thumb.jpg", merged.thumbnailHigh)
        assertEquals("ch1", merged.primaryArtistId)
        assertEquals("Stored Artist", merged.primaryArtistName)
        assertEquals("1M views", merged.viewCountText)
    }

    @Test
    fun mergeCanonicalTrack_updatesNonBlankIncomingFields() {
        val existing = TrackEntity(
            trackId = "vid1",
            title = "Old Title",
            thumbnailHigh = "https://old/thumb.jpg",
            primaryArtistName = "Old Artist",
        )

        val merged = mergeCanonicalTrack(
            existing = existing,
            trackId = "vid1",
            title = "New Title",
            durationSeconds = 180,
            thumbnailUrl = "https://new/thumb.jpg",
            channelId = "ch2",
            channelName = "New Artist",
        )

        assertEquals("New Title", merged.title)
        assertEquals(180, merged.durationSeconds)
        assertEquals("https://new/thumb.jpg", merged.thumbnailHigh)
        assertEquals("ch2", merged.primaryArtistId)
        assertEquals("New Artist", merged.primaryArtistName)
    }

    private fun mergeCanonicalTrack(
        existing: TrackEntity?,
        trackId: String,
        title: String,
        durationSeconds: Int,
        thumbnailUrl: String,
        channelId: String?,
        channelName: String?,
    ): TrackEntity = TrackEntity(
        trackId = trackId,
        title = title.takeIf { it.isNotBlank() } ?: existing?.title.orEmpty(),
        durationSeconds = durationSeconds.takeIf { it > 0 } ?: existing?.durationSeconds ?: 0,
        durationText = existing?.durationText,
        thumbnailLow = existing?.thumbnailLow,
        thumbnailMedium = existing?.thumbnailMedium,
        thumbnailHigh = thumbnailUrl.takeIf { it.isNotBlank() }
            ?: existing?.thumbnailHigh,
        viewCount = existing?.viewCount ?: 0L,
        viewCountText = existing?.viewCountText,
        publishedText = existing?.publishedText,
        primaryArtistId = channelId?.takeIf { it.isNotBlank() } ?: existing?.primaryArtistId,
        primaryArtistName = channelName?.takeIf { it.isNotBlank() } ?: existing?.primaryArtistName,
    )
}
