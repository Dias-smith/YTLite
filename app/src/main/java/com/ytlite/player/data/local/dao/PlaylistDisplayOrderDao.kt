package com.ytlite.player.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.ytlite.player.data.local.entity.PlaylistDisplayOrderEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface PlaylistDisplayOrderDao {
    @Query("SELECT * FROM playlist_display_order WHERE ownerKey = :ownerKey ORDER BY pinGroup DESC, position ASC")
    fun observeByOwner(ownerKey: String): Flow<List<PlaylistDisplayOrderEntity>>

    @Query("SELECT * FROM playlist_display_order WHERE ownerKey = :ownerKey")
    suspend fun getAllByOwner(ownerKey: String): List<PlaylistDisplayOrderEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(entities: List<PlaylistDisplayOrderEntity>)

    @Query("DELETE FROM playlist_display_order WHERE ownerKey = :ownerKey AND playlistKey = :playlistKey")
    suspend fun deleteByKey(ownerKey: String, playlistKey: String)

    @Query("DELETE FROM playlist_display_order WHERE ownerKey = :ownerKey")
    suspend fun deleteAllByOwner(ownerKey: String)
}
