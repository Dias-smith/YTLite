package com.ytlite.player.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.ytlite.player.data.local.entity.ArtistEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface ArtistDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: ArtistEntity)

    @Query("SELECT * FROM artists WHERE artistId = :artistId LIMIT 1")
    suspend fun getById(artistId: String): ArtistEntity?

    @Query("SELECT * FROM artists ORDER BY name COLLATE NOCASE ASC")
    fun observeAll(): Flow<List<ArtistEntity>>
}
