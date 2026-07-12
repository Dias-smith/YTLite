package com.ytlite.player.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.ytlite.player.data.local.entity.PlaylistEntity
import com.ytlite.player.data.model.DataSource
import kotlinx.coroutines.flow.Flow

@Dao
interface PlaylistDao {
    @Query("SELECT * FROM playlists WHERE ownerKey = :ownerKey ORDER BY name ASC")
    fun observeByOwner(ownerKey: String): Flow<List<PlaylistEntity>>

    @Query(
        """
        SELECT * FROM playlists
        WHERE ownerKey = :ownerKey AND source = :localSource
        ORDER BY updatedAt DESC
        """,
    )
    fun observeLocalByOwner(
        ownerKey: String,
        localSource: String = DataSource.LOCAL.dbValue,
    ): Flow<List<PlaylistEntity>>

    @Query(
        """
        SELECT * FROM playlists
        WHERE ownerKey = :ownerKey AND systemType = :systemType AND source = :localSource
        LIMIT 1
        """,
    )
    suspend fun getSystemPlaylist(
        ownerKey: String,
        systemType: String,
        localSource: String = DataSource.LOCAL.dbValue,
    ): PlaylistEntity?

    @Query("SELECT * FROM playlists WHERE playlistId = :playlistId LIMIT 1")
    suspend fun getById(playlistId: String): PlaylistEntity?

    @Query("SELECT * FROM playlists WHERE playlistId = :playlistId LIMIT 1")
    fun observeById(playlistId: String): Flow<PlaylistEntity?>

    @Query(
        """
        SELECT * FROM playlists
        WHERE ownerKey = :ownerKey AND source = :localSource AND isSynced = 0
        """,
    )
    suspend fun getUnsyncedLocalByOwner(
        ownerKey: String,
        localSource: String = DataSource.LOCAL.dbValue,
    ): List<PlaylistEntity>

    @Query("UPDATE playlists SET isSynced = 1 WHERE playlistId = :playlistId")
    suspend fun markSynced(playlistId: String)

    @Query("UPDATE playlists SET isSynced = 0 WHERE playlistId = :playlistId")
    suspend fun markUnsynced(playlistId: String)

    @Query("SELECT * FROM playlists WHERE ownerKey = :ownerKey")
    suspend fun getAllByOwner(ownerKey: String): List<PlaylistEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: PlaylistEntity)

    @Query("DELETE FROM playlists WHERE playlistId = :playlistId")
    suspend fun deleteById(playlistId: String)

    @Query("UPDATE playlists SET ownerKey = :newOwnerKey, userId = :userId WHERE ownerKey = :oldOwnerKey")
    suspend fun migrateOwnerKey(oldOwnerKey: String, newOwnerKey: String, userId: String)
}
