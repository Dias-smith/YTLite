package com.ytlite.player.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.ytlite.player.data.local.entity.DownloadTaskEntity
import com.ytlite.player.data.local.entity.DownloadedItemEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface DownloadDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertTask(task: DownloadTaskEntity)

    @Update
    suspend fun updateTask(task: DownloadTaskEntity)

    @Query("SELECT * FROM download_tasks WHERE id = :id LIMIT 1")
    suspend fun getTask(id: String): DownloadTaskEntity?

    @Query(
        """
        SELECT * FROM download_tasks
        WHERE status IN ('queued','running','paused','failed')
        ORDER BY createdAt ASC
        """,
    )
    fun observeActiveTasks(): Flow<List<DownloadTaskEntity>>

    @Query(
        """
        SELECT * FROM download_tasks
        WHERE status IN ('queued','running')
        ORDER BY createdAt ASC
        """,
    )
    suspend fun getRunnableTasks(): List<DownloadTaskEntity>

    @Query(
        """
        SELECT * FROM download_tasks
        WHERE videoId = :videoId AND itag = :itag
        ORDER BY updatedAt DESC LIMIT 1
        """,
    )
    suspend fun findTaskByVideoAndItag(videoId: String, itag: Int): DownloadTaskEntity?

    @Query("DELETE FROM download_tasks WHERE id = :id")
    suspend fun deleteTask(id: String)

    @Query("SELECT COUNT(*) FROM download_tasks WHERE status = 'running'")
    suspend fun countRunning(): Int

    @Query("SELECT COUNT(*) FROM download_tasks WHERE status IN ('queued','running')")
    suspend fun countActiveWork(): Int

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertDownloaded(item: DownloadedItemEntity)

    @Query("SELECT * FROM downloaded_items ORDER BY completedAt DESC")
    fun observeDownloaded(): Flow<List<DownloadedItemEntity>>

    @Query("SELECT * FROM downloaded_items WHERE id = :id LIMIT 1")
    suspend fun getDownloaded(id: String): DownloadedItemEntity?

    @Query(
        """
        SELECT * FROM downloaded_items
        WHERE videoId = :videoId AND itag = :itag
        LIMIT 1
        """,
    )
    suspend fun findDownloaded(videoId: String, itag: Int): DownloadedItemEntity?

    @Query("DELETE FROM downloaded_items WHERE id = :id")
    suspend fun deleteDownloaded(id: String)

    @Query(
        """
        SELECT * FROM downloaded_items
        WHERE videoId = :videoId
        ORDER BY completedAt DESC
        LIMIT 1
        """,
    )
    suspend fun findAnyDownloaded(videoId: String): DownloadedItemEntity?
}
