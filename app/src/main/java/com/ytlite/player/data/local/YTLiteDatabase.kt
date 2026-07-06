package com.ytlite.player.data.local

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import com.ytlite.player.data.local.dao.ArtistDao
import com.ytlite.player.data.local.dao.PlaybackHistoryDao
import com.ytlite.player.data.local.dao.PlaylistDao
import com.ytlite.player.data.local.dao.PlaylistTrackDao
import com.ytlite.player.data.local.dao.TrackDao
import com.ytlite.player.data.local.dao.UserTrackLastPlayedDao
import com.ytlite.player.data.local.entity.ArtistEntity
import com.ytlite.player.data.local.entity.PlaybackHistoryEntity
import com.ytlite.player.data.local.entity.PlaylistEntity
import com.ytlite.player.data.local.entity.PlaylistTrackEntity
import com.ytlite.player.data.local.entity.TrackEntity
import com.ytlite.player.data.local.entity.UserTrackLastPlayedEntity

@Database(
    entities = [
        ArtistEntity::class,
        TrackEntity::class,
        PlaylistEntity::class,
        PlaylistTrackEntity::class,
        PlaybackHistoryEntity::class,
        UserTrackLastPlayedEntity::class,
    ],
    version = 2,
    exportSchema = false,
)
abstract class YTLiteDatabase : RoomDatabase() {
    abstract fun artistDao(): ArtistDao
    abstract fun trackDao(): TrackDao
    abstract fun playlistDao(): PlaylistDao
    abstract fun playlistTrackDao(): PlaylistTrackDao
    abstract fun playbackHistoryDao(): PlaybackHistoryDao
    abstract fun userTrackLastPlayedDao(): UserTrackLastPlayedDao

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
                    .fallbackToDestructiveMigration()
                    .build()
                    .also { instance = it }
            }
    }
}
