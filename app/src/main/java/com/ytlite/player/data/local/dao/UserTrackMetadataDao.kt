package com.ytlite.player.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.ytlite.player.data.local.entity.UserTrackMetadataEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface UserTrackMetadataDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: UserTrackMetadataEntity)

    @Query("DELETE FROM user_track_metadata WHERE ownerKey = :ownerKey AND trackId = :trackId")
    suspend fun delete(ownerKey: String, trackId: String)

    @Query(
        "SELECT * FROM user_track_metadata WHERE ownerKey = :ownerKey AND trackId = :trackId LIMIT 1",
    )
    suspend fun getById(ownerKey: String, trackId: String): UserTrackMetadataEntity?

    @Query(
        "SELECT * FROM user_track_metadata WHERE ownerKey = :ownerKey AND trackId = :trackId LIMIT 1",
    )
    fun observe(ownerKey: String, trackId: String): Flow<UserTrackMetadataEntity?>

    @Query("SELECT * FROM user_track_metadata WHERE ownerKey = :ownerKey AND isSynced = 0")
    suspend fun getUnsyncedByOwner(ownerKey: String): List<UserTrackMetadataEntity>

    @Query(
        "UPDATE user_track_metadata SET isSynced = 1 WHERE ownerKey = :ownerKey AND trackId = :trackId",
    )
    suspend fun markSynced(ownerKey: String, trackId: String)

    @Query(
        "UPDATE user_track_metadata SET ownerKey = :newOwnerKey WHERE ownerKey = :oldOwnerKey",
    )
    suspend fun migrateOwnerKey(oldOwnerKey: String, newOwnerKey: String)

    @Query("SELECT * FROM user_track_metadata WHERE ownerKey = :ownerKey")
    suspend fun getAllByOwner(ownerKey: String): List<UserTrackMetadataEntity>

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
            COALESCE(u.lastPlayedAt, m.updatedAt, 0) AS lastActivityAt,
            COALESCE(m.updatedAt, 0) AS savedAt
        FROM user_track_metadata m
        INNER JOIN tracks t ON t.trackId = m.trackId
        LEFT JOIN user_track_last_played u ON u.trackId = t.trackId AND u.ownerKey = :ownerKey
        WHERE m.ownerKey = :ownerKey
          AND m.customAlbum IS NOT NULL
          AND TRIM(m.customAlbum) != ''
          AND LOWER(TRIM(m.customAlbum)) = LOWER(TRIM(:album))
        ORDER BY lastActivityAt DESC
        """,
    )
    fun observeTracksByAlbum(
        ownerKey: String,
        album: String,
    ): Flow<List<com.ytlite.player.data.local.model.LibrarySongRow>>

    @Query(
        """
        SELECT
            TRIM(m.customAlbum) AS albumName,
            MAX(COALESCE(u.lastPlayedAt, m.updatedAt, 0)) AS lastActivityAt,
            MAX(COALESCE(m.updatedAt, 0)) AS savedAt
        FROM user_track_metadata m
        LEFT JOIN user_track_last_played u
            ON u.trackId = m.trackId AND u.ownerKey = :ownerKey
        WHERE m.ownerKey = :ownerKey
          AND m.customAlbum IS NOT NULL
          AND TRIM(m.customAlbum) != ''
        GROUP BY LOWER(TRIM(m.customAlbum))
        ORDER BY lastActivityAt DESC
        """,
    )
    fun observeDistinctAlbums(ownerKey: String): Flow<List<com.ytlite.player.data.local.model.LibraryAlbumRow>>
}
