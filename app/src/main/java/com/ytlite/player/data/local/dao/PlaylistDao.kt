package com.ytlite.player.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.ytlite.player.data.local.entity.PlaylistEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface PlaylistDao {
    @Query("SELECT * FROM playlists WHERE ownerKey = :ownerKey ORDER BY name ASC")
    fun observeByOwner(ownerKey: String): Flow<List<PlaylistEntity>>

    @Query(
        """
        SELECT * FROM playlists
        WHERE ownerKey = :ownerKey AND systemType = :systemType
        LIMIT 1
        """,
    )
    suspend fun getSystemPlaylist(ownerKey: String, systemType: String): PlaylistEntity?

    @Query("SELECT * FROM playlists WHERE ownerKey = :ownerKey")
    suspend fun getAllByOwner(ownerKey: String): List<PlaylistEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: PlaylistEntity)

    @Query("UPDATE playlists SET ownerKey = :newOwnerKey, userId = :userId WHERE ownerKey = :oldOwnerKey")
    suspend fun migrateOwnerKey(oldOwnerKey: String, newOwnerKey: String, userId: String)
}
