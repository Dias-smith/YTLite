package com.ytlite.player.data.remote

import com.ytlite.player.data.local.entity.PlaylistEntity
import com.ytlite.player.data.model.DataSource
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class PlaylistSyncMappingTest {

    @Test
    fun playlistEntity_roundTripsThroughDto() {
        val entity = PlaylistEntity(
            playlistId = "playlist-1",
            ownerKey = "user:abc",
            userId = USER_ID,
            name = "Road Trip",
            systemType = null,
            source = DataSource.LOCAL.dbValue,
            isPinned = true,
            updatedAt = 1_700_000_000_000L,
        )

        val dto = entity.toPlaylistDto(USER_ID)
        val restored = dto.toPlaylistEntity(ownerKey = "user:abc", userId = USER_ID)

        assertEquals(entity.playlistId, restored.playlistId)
        assertEquals(entity.name, restored.name)
        assertEquals(entity.isPinned, restored.isPinned)
        assertEquals(entity.updatedAt, restored.updatedAt)
        assertTrue(restored.isSynced)
    }

    @Test
    fun playlistDto_updatedAtMillis_parsesIsoTimestamp() {
        val millis = 1_700_000_000_000L
        val dto = PlaylistEntity(
            playlistId = "playlist-2",
            ownerKey = "user:abc",
            name = "Test",
            updatedAt = millis,
        ).toPlaylistDto(USER_ID)

        assertEquals(millis, dto.updatedAtMillis())
        assertEquals(
            Instant.ofEpochMilli(millis).toString(),
            dto.updatedAt,
        )
    }

    private companion object {
        const val USER_ID = "00000000-0000-0000-0000-000000000001"
    }
}
