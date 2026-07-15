package com.ytlite.player.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.ytlite.player.data.local.entity.UserSubscribedChannelEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface UserSubscribedChannelDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: UserSubscribedChannelEntity)

    @Query(
        """
        DELETE FROM user_subscribed_channels
        WHERE ownerKey = :ownerKey AND channelId = :channelId
        """,
    )
    suspend fun delete(ownerKey: String, channelId: String)

    @Query(
        """
        SELECT * FROM user_subscribed_channels
        WHERE ownerKey = :ownerKey
        ORDER BY subscribedAt DESC
        """,
    )
    fun observeByOwner(ownerKey: String): Flow<List<UserSubscribedChannelEntity>>

    @Query(
        """
        SELECT * FROM user_subscribed_channels
        WHERE ownerKey = :ownerKey
        ORDER BY subscribedAt DESC
        """,
    )
    suspend fun getAllByOwner(ownerKey: String): List<UserSubscribedChannelEntity>

    @Query(
        """
        SELECT * FROM user_subscribed_channels
        WHERE ownerKey = :ownerKey AND channelId = :channelId
        LIMIT 1
        """,
    )
    suspend fun get(ownerKey: String, channelId: String): UserSubscribedChannelEntity?

    @Query(
        """
        SELECT EXISTS(
            SELECT 1 FROM user_subscribed_channels
            WHERE ownerKey = :ownerKey AND channelId = :channelId
        )
        """,
    )
    fun observeIsSubscribed(ownerKey: String, channelId: String): Flow<Boolean>

    @Query(
        """
        SELECT * FROM user_subscribed_channels
        WHERE ownerKey = :ownerKey AND isSynced = 0
        """,
    )
    suspend fun getUnsyncedByOwner(ownerKey: String): List<UserSubscribedChannelEntity>

    @Query(
        """
        UPDATE user_subscribed_channels
        SET isSynced = 1
        WHERE ownerKey = :ownerKey AND channelId = :channelId
        """,
    )
    suspend fun markSynced(ownerKey: String, channelId: String)

    @Query(
        """
        UPDATE user_subscribed_channels
        SET ownerKey = :newOwnerKey, isSynced = 0
        WHERE ownerKey = :oldOwnerKey
        """,
    )
    suspend fun migrateOwnerKey(oldOwnerKey: String, newOwnerKey: String)
}
