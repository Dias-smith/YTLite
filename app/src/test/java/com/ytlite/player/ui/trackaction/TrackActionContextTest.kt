package com.ytlite.player.ui.trackaction

import com.ytlite.player.data.model.DataSource
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TrackActionContextTest {

    @Test
    fun fromQueueItem_mapsAllFields() {
        val context = TrackActionContext.fromQueueItem(
            com.ytlite.player.playback.QueueItem(
                videoId = "v1",
                title = "Title",
                channelName = "Artist",
                thumbnailUrl = "https://thumb",
                album = "Album",
                year = "2020",
            ),
            showRemoveFromQueue = true,
        )

        assertEquals("v1", context.videoId)
        assertEquals("Album", context.album)
        assertEquals("2020", context.year)
        assertTrue(context.showRemoveFromQueue)
        assertEquals(TrackActionSource.QUEUE, context.source)
    }

    @Test
    fun toLibraryVideo_roundTripsCoreFields() {
        val context = TrackActionContext(
            videoId = "v1",
            title = "Title",
            channelName = "Artist",
            thumbnailUrl = "https://thumb",
            channelId = "ch1",
            album = "Album",
            playlistId = "pl1",
            playlistSource = DataSource.LOCAL,
        )

        val video = context.toLibraryVideo()
        assertEquals("v1", video.videoId)
        assertEquals("ch1", video.channelId)
        assertEquals("Album", video.album)
    }

    @Test
    fun fromSearchVideo_usesChannelIdWhenPresent() {
        val context = TrackActionContext.fromSearchVideo(
            com.ytlite.player.data.model.SearchResultItem.Video(
                id = "v1",
                videoId = "v1",
                title = "Title",
                subtitle = "Artist",
                thumbnailUrl = "https://thumb",
                channelName = "Artist",
                channelId = "UC123",
            ),
        )

        assertEquals("UC123", context.channelId)
        assertEquals(TrackActionSource.SEARCH, context.source)
    }

    @Test
    fun toQueueItem_preservesMetadata() {
        val context = TrackActionContext(
            videoId = "v1",
            title = "Title",
            channelName = "Artist",
            thumbnailUrl = "https://thumb",
            album = "Album",
            year = "2021",
        )

        val item = context.toQueueItem()
        assertEquals("Album", item.album)
        assertFalse(context.showRemoveFromQueue)
    }
}
