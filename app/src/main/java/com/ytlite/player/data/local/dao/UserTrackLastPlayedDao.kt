package com.ytlite.player.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.ytlite.player.data.local.entity.UserTrackLastPlayedEntity
import com.ytlite.player.data.local.model.LibraryVideoRow
import kotlinx.coroutines.flow.Flow

@Dao
interface UserTrackLastPlayedDao {
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
            t.durationText AS durationText,
            t.viewCountText AS viewCountText,
            t.publishedText AS publishedText,
            u.lastPlayedAt AS lastPlayedAt,
            u.progressMs AS progressMs
        FROM user_track_last_played u
        INNER JOIN tracks t ON t.trackId = u.trackId
        LEFT JOIN user_track_metadata m ON m.ownerKey = :ownerKey AND m.trackId = t.trackId
        WHERE u.ownerKey = :ownerKey
        ORDER BY u.lastPlayedAt DESC
        LIMIT :limit
        """,
    )
    fun observeHistoryRows(ownerKey: String, limit: Int = 20): Flow<List<LibraryVideoRow>>

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
            t.durationText AS durationText,
            t.viewCountText AS viewCountText,
            t.publishedText AS publishedText,
            u.lastPlayedAt AS lastPlayedAt,
            u.progressMs AS progressMs
        FROM user_track_last_played u
        INNER JOIN tracks t ON t.trackId = u.trackId
        LEFT JOIN user_track_metadata m ON m.ownerKey = :ownerKey AND m.trackId = t.trackId
        WHERE u.ownerKey = :ownerKey
        ORDER BY u.lastPlayedAt DESC
        """,
    )
    fun observeAllHistoryRows(ownerKey: String): Flow<List<LibraryVideoRow>>

    @Query("SELECT * FROM user_track_last_played WHERE ownerKey = :ownerKey")
    suspend fun getAllByOwner(ownerKey: String): List<UserTrackLastPlayedEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: UserTrackLastPlayedEntity)

    @Query("DELETE FROM user_track_last_played WHERE ownerKey = :ownerKey")
    suspend fun deleteByOwner(ownerKey: String)

    @Query("UPDATE user_track_last_played SET ownerKey = :newOwnerKey WHERE ownerKey = :oldOwnerKey")
    suspend fun migrateOwnerKey(oldOwnerKey: String, newOwnerKey: String)
}
