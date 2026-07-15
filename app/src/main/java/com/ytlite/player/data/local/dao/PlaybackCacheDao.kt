package com.ytlite.player.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.ytlite.player.data.local.entity.PlaybackCacheEntity

@Dao
interface PlaybackCacheDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: PlaybackCacheEntity)

    @Query("SELECT * FROM playback_media_cache")
    suspend fun getAll(): List<PlaybackCacheEntity>

    @Query("SELECT * FROM playback_media_cache WHERE videoId = :videoId")
    suspend fun get(videoId: String): PlaybackCacheEntity?

    @Query("DELETE FROM playback_media_cache WHERE videoId = :videoId")
    suspend fun delete(videoId: String)

    @Query(
        """
        UPDATE playback_media_cache
        SET historyOnlySince = :historyOnlySince
        WHERE videoId = :videoId
        """,
    )
    suspend fun updateHistoryOnlySince(videoId: String, historyOnlySince: Long?)

    @Query(
        """
        UPDATE playback_media_cache
        SET lastPlayedAt = :lastPlayedAt, cacheKey = :cacheKey, itag = :itag, historyOnlySince = :historyOnlySince
        WHERE videoId = :videoId
        """,
    )
    suspend fun updatePlayback(
        videoId: String,
        cacheKey: String,
        itag: Int?,
        lastPlayedAt: Long,
        historyOnlySince: Long?,
    )
}
