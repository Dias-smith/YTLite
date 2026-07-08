package com.ytlite.player.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.ytlite.player.data.local.entity.SearchRecentClickEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface SearchRecentClickDao {
    @Query("SELECT * FROM search_recent_clicks ORDER BY clickedAt DESC LIMIT 20")
    fun observeRecentClicks(): Flow<List<SearchRecentClickEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: SearchRecentClickEntity)

    @Query("DELETE FROM search_recent_clicks WHERE targetId = :targetId")
    suspend fun deleteById(targetId: String)

    @Query("DELETE FROM search_recent_clicks")
    suspend fun clearAll()
}
