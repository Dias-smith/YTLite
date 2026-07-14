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

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(entities: List<PlaylistTrackEntity>)

    @Query("DELETE FROM playlist_track_cross_ref WHERE playlistId = :playlistId")
    suspend fun deleteAllByPlaylist(playlistId: String)

    @Query("UPDATE playlist_track_cross_ref SET isSynced = 1 WHERE playlistId = :playlistId")
    suspend fun markSyncedByPlaylist(playlistId: String)

    @Query("DELETE FROM playlist_track_cross_ref WHERE playlistId = :playlistId AND trackId = :trackId")
    suspend fun deleteTrack(playlistId: String, trackId: String)

    @Query(
        """
        DELETE FROM playlist_track_cross_ref
        WHERE trackId = :trackId
          AND playlistId IN (
            SELECT playlistId FROM playlists
            WHERE ownerKey = :ownerKey AND source = :localSource
          )
        """,
    )
    suspend fun deleteTrackFromAllLocalPlaylists(
        ownerKey: String,
        trackId: String,
        localSource: String = com.ytlite.player.data.model.DataSource.LOCAL.dbValue,
    )

    @Query(
        """
        SELECT EXISTS(
            SELECT 1 FROM playlist_track_cross_ref p
            INNER JOIN playlists pl ON pl.playlistId = p.playlistId
            WHERE pl.ownerKey = :ownerKey AND p.trackId = :trackId
        )
        """,
    )
    suspend fun isTrackInAnyPlaylist(ownerKey: String, trackId: String): Boolean

    @Query(
        """
        SELECT EXISTS(
            SELECT 1 FROM playlist_track_cross_ref p
            INNER JOIN playlists pl ON pl.playlistId = p.playlistId
            WHERE pl.ownerKey = :ownerKey AND pl.systemType = :systemType AND p.trackId = :trackId
        )
        """,
    )
    fun observeTrackInSystemPlaylist(
        ownerKey: String,
        systemType: String,
        trackId: String,
    ): Flow<Boolean>

    @Query(
        """
        SELECT
            t.trackId AS trackId,
            COALESCE(m.customTitle, t.title) AS title,
            COALESCE(m.customArtistName, t.primaryArtistName) AS primaryArtistName,
            t.primaryArtistId AS primaryArtistId,
            COALESCE(m.customThumbnailUrl, t.thumbnailHigh, t.thumbnailMedium, t.thumbnailLow, '') AS thumbnailUrl,
            m.customAlbum AS album,
            m.customYear AS year,
            MAX(COALESCE(u.lastPlayedAt, p.createdAt)) AS lastActivityAt,
            MAX(p.createdAt) AS savedAt
        FROM playlist_track_cross_ref p
        INNER JOIN playlists pl ON pl.playlistId = p.playlistId
        INNER JOIN tracks t ON t.trackId = p.trackId
        LEFT JOIN user_track_last_played u ON u.trackId = t.trackId AND u.ownerKey = :ownerKey
        LEFT JOIN user_track_metadata m ON m.ownerKey = :ownerKey AND m.trackId = t.trackId
        WHERE pl.ownerKey = :ownerKey AND pl.source = :localSource
        GROUP BY t.trackId
        ORDER BY lastActivityAt DESC
        """,
    )
    fun observeLocalSongs(
        ownerKey: String,
        localSource: String = com.ytlite.player.data.model.DataSource.LOCAL.dbValue,
    ): Flow<List<com.ytlite.player.data.local.model.LibrarySongRow>>

    @Query(
        """
        SELECT
            t.trackId AS trackId,
            COALESCE(m.customTitle, t.title) AS title,
            COALESCE(m.customArtistName, t.primaryArtistName) AS primaryArtistName,
            t.primaryArtistId AS primaryArtistId,
            COALESCE(m.customThumbnailUrl, t.thumbnailHigh, t.thumbnailMedium, t.thumbnailLow, '') AS thumbnailUrl,
            m.customAlbum AS album,
            m.customYear AS year,
            t.durationSeconds AS durationSeconds,
            t.durationText AS durationText,
            p.position AS position,
            p.createdAt AS addedAt
        FROM playlist_track_cross_ref p
        INNER JOIN tracks t ON t.trackId = p.trackId
        INNER JOIN playlists pl ON pl.playlistId = p.playlistId
        LEFT JOIN user_track_metadata m ON m.ownerKey = pl.ownerKey AND m.trackId = t.trackId
        WHERE p.playlistId = :playlistId
        ORDER BY p.position ASC
        """,
    )
    fun observePlaylistTrackDetails(playlistId: String): Flow<List<com.ytlite.player.data.local.model.PlaylistTrackDetailRow>>

    @Query(
        """
        SELECT
            COUNT(*) AS trackCount,
            COALESCE(SUM(t.durationSeconds), 0) AS totalDurationSeconds
        FROM playlist_track_cross_ref p
        INNER JOIN tracks t ON t.trackId = p.trackId
        WHERE p.playlistId = :playlistId
        """,
    )
    fun observePlaylistStats(playlistId: String): Flow<com.ytlite.player.data.local.model.PlaylistStatsRow>

    @Query(
        """
        UPDATE playlist_track_cross_ref
        SET playlistId = :newPlaylistId
        WHERE playlistId = :oldPlaylistId
        """,
    )
    suspend fun migratePlaylistId(oldPlaylistId: String, newPlaylistId: String)
}
