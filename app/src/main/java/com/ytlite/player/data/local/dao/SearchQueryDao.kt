package com.ytlite.player.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.ytlite.player.data.local.entity.SearchQueryEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface SearchQueryDao {
    @Query("SELECT * FROM search_queries ORDER BY accessedAt DESC LIMIT 15")
    fun observeRecentQueries(): Flow<List<SearchQueryEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: SearchQueryEntity)

    @Query("DELETE FROM search_queries WHERE query NOT IN (SELECT query FROM search_queries ORDER BY accessedAt DESC LIMIT 15)")
    suspend fun trimToLimit()

    @Query("DELETE FROM search_queries")
    suspend fun clearAll()
}
