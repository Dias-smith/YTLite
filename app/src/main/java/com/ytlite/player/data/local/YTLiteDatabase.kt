package com.ytlite.player.data.local

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import com.ytlite.player.data.local.dao.ArtistDao
import com.ytlite.player.data.local.dao.DownloadDao
import com.ytlite.player.data.local.dao.NotInterestedDao
import com.ytlite.player.data.local.dao.PlaybackCacheDao
import com.ytlite.player.data.local.dao.PlaybackHistoryDao
import com.ytlite.player.data.local.dao.PlaylistDisplayOrderDao
import com.ytlite.player.data.local.dao.PlaylistDao
import com.ytlite.player.data.local.dao.PlaylistPinOverlayDao
import com.ytlite.player.data.local.dao.PlaylistTrackDao
import com.ytlite.player.data.local.dao.SearchQueryDao
import com.ytlite.player.data.local.dao.SearchRecentClickDao
import com.ytlite.player.data.local.dao.TrackDao
import com.ytlite.player.data.local.dao.UserSubscribedChannelDao
import com.ytlite.player.data.local.dao.UserTrackLastPlayedDao
import com.ytlite.player.data.local.dao.UserTrackMetadataDao
import com.ytlite.player.data.local.entity.ArtistEntity
import com.ytlite.player.data.local.entity.DownloadTaskEntity
import com.ytlite.player.data.local.entity.DownloadedItemEntity
import com.ytlite.player.data.local.entity.NotInterestedEntity
import com.ytlite.player.data.local.entity.PlaybackCacheEntity
import com.ytlite.player.data.local.entity.PlaybackHistoryEntity
import com.ytlite.player.data.local.entity.PlaylistDisplayOrderEntity
import com.ytlite.player.data.local.entity.PlaylistEntity
import com.ytlite.player.data.local.entity.PlaylistPinOverlayEntity
import com.ytlite.player.data.local.entity.PlaylistTrackEntity
import com.ytlite.player.data.local.entity.SearchQueryEntity
import com.ytlite.player.data.local.entity.SearchRecentClickEntity
import com.ytlite.player.data.local.entity.TrackEntity
import com.ytlite.player.data.local.entity.UserSubscribedChannelEntity
import com.ytlite.player.data.local.entity.UserTrackLastPlayedEntity
import com.ytlite.player.data.local.entity.UserTrackMetadataEntity

@Database(
    entities = [
        ArtistEntity::class,
        TrackEntity::class,
        PlaylistEntity::class,
        PlaylistPinOverlayEntity::class,
        PlaylistDisplayOrderEntity::class,
        PlaylistTrackEntity::class,
        PlaybackHistoryEntity::class,
        UserTrackLastPlayedEntity::class,
        SearchQueryEntity::class,
        SearchRecentClickEntity::class,
        NotInterestedEntity::class,
        UserTrackMetadataEntity::class,
        UserSubscribedChannelEntity::class,
        PlaybackCacheEntity::class,
        DownloadTaskEntity::class,
        DownloadedItemEntity::class,
    ],
    version = 13,
    exportSchema = false,
)
abstract class YTLiteDatabase : RoomDatabase() {
    abstract fun artistDao(): ArtistDao
    abstract fun trackDao(): TrackDao
    abstract fun playlistDao(): PlaylistDao
    abstract fun playlistPinOverlayDao(): PlaylistPinOverlayDao
    abstract fun playlistDisplayOrderDao(): PlaylistDisplayOrderDao
    abstract fun playlistTrackDao(): PlaylistTrackDao
    abstract fun playbackHistoryDao(): PlaybackHistoryDao
    abstract fun userTrackLastPlayedDao(): UserTrackLastPlayedDao
    abstract fun searchQueryDao(): SearchQueryDao
    abstract fun searchRecentClickDao(): SearchRecentClickDao
    abstract fun notInterestedDao(): NotInterestedDao
    abstract fun userTrackMetadataDao(): UserTrackMetadataDao
    abstract fun userSubscribedChannelDao(): UserSubscribedChannelDao
    abstract fun playbackCacheDao(): PlaybackCacheDao
    abstract fun downloadDao(): DownloadDao

    companion object {
        @Volatile
        private var instance: YTLiteDatabase? = null

        fun getInstance(context: Context): YTLiteDatabase =
            instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(
                    context.applicationContext,
                    YTLiteDatabase::class.java,
                    "ytlite.db",
                )
                    .addMigrations(
                        MIGRATION_6_7,
                        MIGRATION_7_8,
                        MIGRATION_8_9,
                        MIGRATION_9_10,
                        MIGRATION_10_11,
                        MIGRATION_11_12,
                        MIGRATION_12_13,
                    )
                    .build()
                    .also { instance = it }
            }
    }
}
