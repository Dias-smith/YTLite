package com.ytlite.player.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.ytlite.player.data.local.entity.PlaylistPinOverlayEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface PlaylistPinOverlayDao {
    @Query("SELECT * FROM playlist_pin_overlay WHERE ownerKey = :ownerKey")
    fun observeByOwner(ownerKey: String): Flow<List<PlaylistPinOverlayEntity>>

    @Query(
        """
        SELECT * FROM playlist_pin_overlay
        WHERE playlistId = :playlistId AND ownerKey = :ownerKey
        LIMIT 1
        """,
    )
    fun observeByPlaylist(ownerKey: String, playlistId: String): Flow<PlaylistPinOverlayEntity?>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: PlaylistPinOverlayEntity)

    @Query(
        """
        DELETE FROM playlist_pin_overlay
        WHERE playlistId = :playlistId AND ownerKey = :ownerKey
        """,
    )
    suspend fun delete(ownerKey: String, playlistId: String)
}
