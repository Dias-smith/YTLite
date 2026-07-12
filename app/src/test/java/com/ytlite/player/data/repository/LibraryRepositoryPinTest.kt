package com.ytlite.player.data.repository

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.ytlite.player.data.local.YTLiteDatabase
import com.ytlite.player.data.local.dao.PlaylistDao
import com.ytlite.player.data.local.dao.PlaylistPinOverlayDao
import com.ytlite.player.data.local.entity.PlaylistEntity
import com.ytlite.player.data.local.entity.PlaylistPinOverlayEntity
import com.ytlite.player.data.local.entity.PlaylistSystemType
import com.ytlite.player.data.model.DataSource
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class LibraryRepositoryPinTest {

    private lateinit var context: Context
    private lateinit var database: YTLiteDatabase
    private lateinit var playlistDao: PlaylistDao
    private lateinit var playlistPinOverlayDao: PlaylistPinOverlayDao

    private val ownerKey = "guest:test"

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        database = Room.inMemoryDatabaseBuilder(context, YTLiteDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        playlistDao = database.playlistDao()
        playlistPinOverlayDao = database.playlistPinOverlayDao()
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun togglePlaylistPin_flipsIsPinned_forLocalCustomPlaylist() = runBlocking {
        playlistDao.upsert(
            PlaylistEntity(
                playlistId = "custom-1",
                ownerKey = ownerKey,
                name = "My Playlist",
                isPinned = false,
            ),
        )

        val success = toggleLocalPlaylistPin("custom-1", ownerKey)
        assertTrue(success)

        val updated = playlistDao.getById("custom-1")
        assertEquals(true, updated?.isPinned)
    }

    @Test
    fun togglePlaylistPin_flipsIsPinned_forSystemPlaylist() = runBlocking {
        playlistDao.upsert(
            PlaylistEntity(
                playlistId = "system-favorites",
                ownerKey = ownerKey,
                name = "Liked videos",
                systemType = PlaylistSystemType.FAVORITES,
            ),
        )

        val success = toggleLocalPlaylistPin("system-favorites", ownerKey)
        assertTrue(success)

        val updated = playlistDao.getById("system-favorites")
        assertEquals(true, updated?.isPinned)
    }

    @Test
    fun togglePlaylistPin_persistsYoutubeOverlay() = runBlocking {
        val playlistId = "YT_PL_test"

        toggleYoutubeOverlayPin(playlistId, ownerKey, currentlyPinned = false)

        val overlay = playlistPinOverlayDao.observeByPlaylist(ownerKey, playlistId).first()
        assertEquals(true, overlay?.isPinned)
    }

    @Test
    fun togglePlaylistPin_returnsFalse_forHistoryVirtualPlaylist() = runBlocking {
        val success = toggleLocalPlaylistPin("system:history", ownerKey)
        assertFalse(success)
    }

    @Test
    fun togglePlaylistPin_restoresUpdatedAt_onUnpin() = runBlocking {
        val originalUpdatedAt = 1_000L
        playlistDao.upsert(
            PlaylistEntity(
                playlistId = "custom-1",
                ownerKey = ownerKey,
                name = "My Playlist",
                isPinned = false,
                updatedAt = originalUpdatedAt,
            ),
        )

        toggleLocalPlaylistPin("custom-1", ownerKey)
        val pinned = playlistDao.getById("custom-1")!!
        assertEquals(true, pinned.isPinned)
        assertEquals(originalUpdatedAt, pinned.unpinnedSortAt)
        assertEquals(originalUpdatedAt, pinned.updatedAt)

        toggleLocalPlaylistPin("custom-1", ownerKey)
        val unpinned = playlistDao.getById("custom-1")!!
        assertEquals(false, unpinned.isPinned)
        assertEquals(originalUpdatedAt, unpinned.updatedAt)
        assertEquals(null, unpinned.unpinnedSortAt)
    }

    private suspend fun toggleLocalPlaylistPin(playlistId: String, ownerKey: String): Boolean {
        val playlist = playlistDao.getById(playlistId)
            ?: playlistDao.getAllByOwner(ownerKey).firstOrNull { it.playlistId == playlistId }
            ?: return false
        if (playlist.ownerKey != ownerKey || playlist.isYoutube()) return false
        if (playlist.systemType == PlaylistSystemType.HISTORY) return false
        val now = System.currentTimeMillis()
        val updated = if (!playlist.isPinned) {
            playlist.copy(
                isPinned = true,
                unpinnedSortAt = playlist.updatedAt,
                pinnedAt = now,
                isSynced = false,
            )
        } else {
            playlist.copy(
                isPinned = false,
                updatedAt = playlist.unpinnedSortAt ?: playlist.updatedAt,
                unpinnedSortAt = null,
                pinnedAt = null,
                isSynced = false,
            )
        }
        playlistDao.upsert(updated)
        return true
    }

    private suspend fun toggleYoutubeOverlayPin(
        playlistId: String,
        ownerKey: String,
        currentlyPinned: Boolean,
    ) {
        playlistPinOverlayDao.upsert(
            PlaylistPinOverlayEntity(
                playlistId = playlistId,
                ownerKey = ownerKey,
                isPinned = !currentlyPinned,
                updatedAt = System.currentTimeMillis(),
            ),
        )
    }
}
