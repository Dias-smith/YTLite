package com.ytlite.player.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.ytlite.player.data.local.entity.NotInterestedEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface NotInterestedDao {

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: NotInterestedEntity)

    @Query("DELETE FROM not_interested WHERE ownerKey = :ownerKey AND videoId = :videoId")
    suspend fun delete(ownerKey: String, videoId: String)

    @Query(
        "SELECT EXISTS(SELECT 1 FROM not_interested WHERE ownerKey = :ownerKey AND videoId = :videoId)",
    )
    fun observeIsNotInterested(ownerKey: String, videoId: String): Flow<Boolean>
}
