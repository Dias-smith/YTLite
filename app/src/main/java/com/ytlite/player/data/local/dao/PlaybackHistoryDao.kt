package com.ytlite.player.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.ytlite.player.data.local.entity.PlaybackHistoryEntity

@Dao
interface PlaybackHistoryDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: PlaybackHistoryEntity)

    @Query("SELECT * FROM playback_history WHERE ownerKey = :ownerKey AND isSynced = 0")
    suspend fun getUnsyncedByOwner(ownerKey: String): List<PlaybackHistoryEntity>

    @Query("UPDATE playback_history SET isSynced = 1 WHERE historyId = :historyId")
    suspend fun markSynced(historyId: String)

    @Query("UPDATE playback_history SET ownerKey = :newOwnerKey WHERE ownerKey = :oldOwnerKey")
    suspend fun migrateOwnerKey(oldOwnerKey: String, newOwnerKey: String)
}
