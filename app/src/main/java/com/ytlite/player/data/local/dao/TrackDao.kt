package com.ytlite.player.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.ytlite.player.data.local.entity.TrackEntity

@Dao
interface TrackDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: TrackEntity)

    @Query("SELECT * FROM tracks WHERE trackId = :trackId LIMIT 1")
    suspend fun getById(trackId: String): TrackEntity?

    @Query("SELECT * FROM tracks WHERE trackId IN (:trackIds)")
    suspend fun getByIds(trackIds: List<String>): List<TrackEntity>

    @Query(
        """
        SELECT COALESCE(thumbnailHigh, thumbnailMedium, thumbnailLow)
        FROM tracks
        WHERE primaryArtistId = :artistId
          AND COALESCE(thumbnailHigh, thumbnailMedium, thumbnailLow) IS NOT NULL
          AND TRIM(COALESCE(thumbnailHigh, thumbnailMedium, thumbnailLow)) != ''
        LIMIT 1
        """,
    )
    suspend fun findThumbnailByArtistId(artistId: String): String?
}
