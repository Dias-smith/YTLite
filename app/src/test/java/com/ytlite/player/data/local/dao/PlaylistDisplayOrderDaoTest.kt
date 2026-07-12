package com.ytlite.player.data.local.dao

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.ytlite.player.data.local.YTLiteDatabase
import com.ytlite.player.data.local.entity.PlaylistDisplayOrderEntity
import com.ytlite.player.data.model.DataSource
import com.ytlite.player.data.model.LibraryItem
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class PlaylistDisplayOrderDaoTest {

    private lateinit var context: Context
    private lateinit var database: YTLiteDatabase
    private lateinit var displayOrderDao: PlaylistDisplayOrderDao

    private val ownerKey = "guest:test"

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        database = Room.inMemoryDatabaseBuilder(context, YTLiteDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        displayOrderDao = database.playlistDisplayOrderDao()
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun seedDisplayOrderFromCurrent_assignsPositionsPerPinGroup() = runBlocking {
        val items = listOf(
            playlist(id = "pinned-1", isPinned = true),
            playlist(id = "pinned-2", isPinned = true),
            playlist(id = "unpinned-1"),
            playlist(id = "unpinned-2"),
        )

        seedDisplayOrderFromCurrent(ownerKey, items)

        val stored = displayOrderDao.getAllByOwner(ownerKey).sortedWith(
            compareBy({ !it.pinGroup }, { it.position }),
        )
        assertEquals(
            listOf(
                PlaylistDisplayOrderEntity(ownerKey, "pinned-1", pinGroup = true, position = 0),
                PlaylistDisplayOrderEntity(ownerKey, "pinned-2", pinGroup = true, position = 1),
                PlaylistDisplayOrderEntity(ownerKey, "unpinned-1", pinGroup = false, position = 0),
                PlaylistDisplayOrderEntity(ownerKey, "unpinned-2", pinGroup = false, position = 1),
            ),
            stored,
        )
    }

    @Test
    fun reorderPlaylistInGroup_rewritesPositionsWithinGroup() = runBlocking {
        displayOrderDao.upsertAll(
            listOf(
                PlaylistDisplayOrderEntity(ownerKey, "a", pinGroup = false, position = 0),
                PlaylistDisplayOrderEntity(ownerKey, "b", pinGroup = false, position = 1),
                PlaylistDisplayOrderEntity(ownerKey, "c", pinGroup = false, position = 2),
            ),
        )

        reorderPlaylistInGroup(ownerKey, pinGroup = false, fromPosition = 0, toPosition = 2)

        val positions = displayOrderDao.getAllByOwner(ownerKey)
            .filter { !it.pinGroup }
            .sortedBy { it.position }
            .map { it.playlistKey to it.position }
        assertEquals(listOf("b" to 0, "c" to 1, "a" to 2), positions)
    }

    @Test
    fun moveDisplayOrderOnPinToggle_movesEntryToTargetGroupEnd() = runBlocking {
        displayOrderDao.upsertAll(
            listOf(
                PlaylistDisplayOrderEntity(ownerKey, "pinned-1", pinGroup = true, position = 0),
                PlaylistDisplayOrderEntity(ownerKey, "item", pinGroup = false, position = 0),
                PlaylistDisplayOrderEntity(ownerKey, "unpinned-2", pinGroup = false, position = 1),
            ),
        )

        moveDisplayOrderOnPinToggle(ownerKey, playlistKey = "item", nowPinned = true)

        val stored = displayOrderDao.getAllByOwner(ownerKey)
        assertEquals(
            listOf(
                PlaylistDisplayOrderEntity(ownerKey, "pinned-1", pinGroup = true, position = 0),
                PlaylistDisplayOrderEntity(ownerKey, "item", pinGroup = true, position = 1),
                PlaylistDisplayOrderEntity(ownerKey, "unpinned-2", pinGroup = false, position = 1),
            ),
            stored.sortedWith(compareBy({ !it.pinGroup }, { it.position }, { it.playlistKey })),
        )
    }

    private suspend fun seedDisplayOrderFromCurrent(
        ownerKey: String,
        items: List<LibraryItem.Playlist>,
    ) {
        val entities = buildList {
            items.filter { it.isPinned }.forEachIndexed { index, item ->
                add(
                    PlaylistDisplayOrderEntity(
                        ownerKey = ownerKey,
                        playlistKey = item.id,
                        pinGroup = true,
                        position = index,
                    ),
                )
            }
            items.filter { !it.isPinned }.forEachIndexed { index, item ->
                add(
                    PlaylistDisplayOrderEntity(
                        ownerKey = ownerKey,
                        playlistKey = item.id,
                        pinGroup = false,
                        position = index,
                    ),
                )
            }
        }
        displayOrderDao.upsertAll(entities)
    }

    private suspend fun reorderPlaylistInGroup(
        ownerKey: String,
        pinGroup: Boolean,
        fromPosition: Int,
        toPosition: Int,
    ) {
        val group = displayOrderDao.getAllByOwner(ownerKey)
            .filter { it.pinGroup == pinGroup }
            .sortedBy { it.position }
            .toMutableList()
        if (fromPosition !in group.indices || toPosition !in group.indices) return
        val moved = group.removeAt(fromPosition)
        group.add(toPosition, moved)
        displayOrderDao.upsertAll(
            group.mapIndexed { index, entity -> entity.copy(position = index) },
        )
    }

    private suspend fun moveDisplayOrderOnPinToggle(
        ownerKey: String,
        playlistKey: String,
        nowPinned: Boolean,
    ) {
        val all = displayOrderDao.getAllByOwner(ownerKey)
        if (all.isEmpty()) return
        displayOrderDao.deleteByKey(ownerKey, playlistKey)
        val targetGroup = all.filter { it.pinGroup == nowPinned && it.playlistKey != playlistKey }
        val newPosition = (targetGroup.maxOfOrNull { it.position } ?: -1) + 1
        displayOrderDao.upsertAll(
            listOf(
                PlaylistDisplayOrderEntity(
                    ownerKey = ownerKey,
                    playlistKey = playlistKey,
                    pinGroup = nowPinned,
                    position = newPosition,
                ),
            ),
        )
    }

    private fun playlist(
        id: String,
        isPinned: Boolean = false,
    ) = LibraryItem.Playlist(
        id = id,
        playlistId = id,
        title = id,
        subtitle = "subtitle",
        coverUrl = null,
        source = DataSource.LOCAL,
        sortKeyActivity = 0L,
        sortKeySaved = 0L,
        isPinned = isPinned,
    )
}
