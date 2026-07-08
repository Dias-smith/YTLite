package com.ytlite.player.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.ytlite.player.data.local.entity.PlaylistTrackEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface PlaylistTrackDao {
    @Query(
        """
        SELECT COUNT(*) FROM playlist_track_cross_ref p
        INNER JOIN playlists pl ON pl.playlistId = p.playlistId
        WHERE pl.ownerKey = :ownerKey AND pl.systemType = :systemType
        """,
    )
    fun observeSystemPlaylistCount(ownerKey: String, systemType: String): Flow<Int>

    @Query("SELECT * FROM playlist_track_cross_ref WHERE playlistId = :playlistId ORDER BY position ASC")
    fun observeTracksInPlaylist(playlistId: String): Flow<List<PlaylistTrackEntity>>

    @Query("SELECT * FROM playlist_track_cross_ref WHERE playlistId = :playlistId")
    suspend fun getAllByPlaylist(playlistId: String): List<PlaylistTrackEntity>

    @Query("SELECT * FROM playlist_track_cross_ref WHERE isSynced = 0")
    suspend fun getUnsynced(): List<PlaylistTrackEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: PlaylistTrackEntity)

    @Query("DELETE FROM playlist_track_cross_ref WHERE playlistId = :playlistId")
    suspend fun deleteAllByPlaylist(playlistId: String)

    @Query(
        """
        UPDATE playlist_track_cross_ref
        SET playlistId = :newPlaylistId
        WHERE playlistId = :oldPlaylistId
        """,
    )
    suspend fun migratePlaylistId(oldPlaylistId: String, newPlaylistId: String)
}
