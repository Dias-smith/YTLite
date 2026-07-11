package com.ytlite.player.data.repository

import com.ytlite.player.data.local.entity.TrackEntity
import com.ytlite.player.data.local.entity.UserTrackMetadataEntity
import com.ytlite.player.data.model.TrackMetadataEdits
import com.ytlite.player.playback.NowPlaying
import com.ytlite.player.playback.QueueItem
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TrackMetadataResolverTest {

    private val canonical = TrackEntity(
        trackId = "vid1",
        title = "YouTube Title",
        thumbnailHigh = "https://yt/thumb.jpg",
        primaryArtistName = "YouTube Artist",
    )

    @Test
    fun resolve_withoutOverride_returnsCanonical() {
        val resolved = TrackMetadataResolver.resolve(canonical, override = null)

        assertEquals("YouTube Title", resolved.title)
        assertEquals("YouTube Artist", resolved.artistName)
        assertEquals("https://yt/thumb.jpg", resolved.thumbnailUrl)
        assertNull(resolved.album)
        assertNull(resolved.year)
        assertFalse(resolved.hasUserOverride)
    }

    @Test
    fun resolve_withPartialOverride_coalescesFields() {
        val override = UserTrackMetadataEntity(
            ownerKey = "user:1",
            trackId = "vid1",
            customTitle = "My Title",
            updatedAt = 1L,
        )

        val resolved = TrackMetadataResolver.resolve(canonical, override)

        assertEquals("My Title", resolved.title)
        assertEquals("YouTube Artist", resolved.artistName)
        assertEquals("https://yt/thumb.jpg", resolved.thumbnailUrl)
        assertTrue(resolved.hasUserOverride)
    }

    @Test
    fun resolve_withFullOverride_usesAllCustomFields() {
        val override = UserTrackMetadataEntity(
            ownerKey = "user:1",
            trackId = "vid1",
            customTitle = "Custom",
            customArtistName = "Artist",
            customThumbnailUrl = "https://custom/thumb.jpg",
            customAlbum = "Album",
            customYear = "2020",
            updatedAt = 1L,
        )

        val resolved = TrackMetadataResolver.resolve(canonical, override)

        assertEquals("Custom", resolved.title)
        assertEquals("Artist", resolved.artistName)
        assertEquals("https://custom/thumb.jpg", resolved.thumbnailUrl)
        assertEquals("Album", resolved.album)
        assertEquals("2020", resolved.year)
        assertTrue(resolved.hasUserOverride)
    }

    @Test
    fun resolve_withBlankOverrideFields_fallsBackToCanonical() {
        val override = UserTrackMetadataEntity(
            ownerKey = "user:1",
            trackId = "vid1",
            customTitle = "  ",
            customArtistName = "",
            customAlbum = "Only Album",
            updatedAt = 1L,
        )

        val resolved = TrackMetadataResolver.resolve(canonical, override)

        assertEquals("YouTube Title", resolved.title)
        assertEquals("YouTube Artist", resolved.artistName)
        assertEquals("Only Album", resolved.album)
        assertTrue(resolved.hasUserOverride)
    }

    @Test
    fun resolveForQueueItem_mergesOverrideWithQueueItem() {
        val item = QueueItem(
            videoId = "vid1",
            title = "Queue Title",
            channelName = "Queue Channel",
            thumbnailUrl = "https://queue/thumb.jpg",
            album = "Queue Album",
            year = "2019",
        )
        val override = UserTrackMetadataEntity(
            ownerKey = "user:1",
            trackId = "vid1",
            customTitle = "Edited",
            updatedAt = 1L,
        )

        val resolved = TrackMetadataResolver.resolveForQueueItem(item, override)

        assertEquals("Edited", resolved.title)
        assertEquals("Queue Channel", resolved.artistName)
        assertEquals("https://queue/thumb.jpg", resolved.thumbnailUrl)
        assertEquals("Queue Album", resolved.album)
        assertEquals("2019", resolved.year)
    }

    @Test
    fun resolveForNowPlaying_usesOverrideAlbumAndYear() {
        val nowPlaying = NowPlaying(
            videoId = "vid1",
            title = "Now Title",
            channelName = "Now Channel",
            streamUrl = "https://stream",
            thumbnailUrl = "https://now/thumb.jpg",
        )
        val override = UserTrackMetadataEntity(
            ownerKey = "user:1",
            trackId = "vid1",
            customAlbum = "Live",
            customYear = "2024",
            updatedAt = 1L,
        )

        val resolved = TrackMetadataResolver.resolveForNowPlaying(nowPlaying, override)

        assertEquals("Live", resolved.album)
        assertEquals("2024", resolved.year)
    }

    @Test
    fun editsDifferFromCanonical_detectsAlbumYearOnlyChanges() {
        val edits = TrackMetadataEdits(album = "New Album")

        assertTrue(TrackMetadataResolver.editsDifferFromCanonical(canonical, edits))
    }

    @Test
    fun editsDifferFromCanonical_returnsFalseWhenMatchingCanonical() {
        val edits = TrackMetadataEdits(
            title = canonical.title,
            artistName = canonical.primaryArtistName,
            thumbnailUrl = canonical.thumbnailHigh,
        )

        assertFalse(TrackMetadataResolver.editsDifferFromCanonical(canonical, edits))
    }
}
