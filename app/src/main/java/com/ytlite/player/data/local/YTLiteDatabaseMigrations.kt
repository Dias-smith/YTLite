package com.ytlite.player.data.local

import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

val MIGRATION_6_7 = object : Migration(6, 7) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL(
            "ALTER TABLE playlists ADD COLUMN isPinned INTEGER NOT NULL DEFAULT 0",
        )
    }
}

val MIGRATION_7_8 = object : Migration(7, 8) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS playlist_pin_overlay (
                playlistId TEXT NOT NULL,
                ownerKey TEXT NOT NULL,
                isPinned INTEGER NOT NULL DEFAULT 0,
                updatedAt INTEGER NOT NULL,
                PRIMARY KEY(playlistId, ownerKey)
            )
            """.trimIndent(),
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS index_playlist_pin_overlay_ownerKey ON playlist_pin_overlay(ownerKey)",
        )
    }
}

val MIGRATION_8_9 = object : Migration(8, 9) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE playlists ADD COLUMN unpinnedSortAt INTEGER")
        db.execSQL("ALTER TABLE playlists ADD COLUMN pinnedAt INTEGER")
        db.execSQL("ALTER TABLE playlist_pin_overlay ADD COLUMN unpinnedSortAt INTEGER")
        db.execSQL("ALTER TABLE playlist_pin_overlay ADD COLUMN pinnedAt INTEGER")
    }
}

val MIGRATION_9_10 = object : Migration(9, 10) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS playlist_display_order (
                ownerKey TEXT NOT NULL,
                playlistKey TEXT NOT NULL,
                pinGroup INTEGER NOT NULL,
                position INTEGER NOT NULL,
                PRIMARY KEY(ownerKey, playlistKey)
            )
            """.trimIndent(),
        )
        db.execSQL(
            "CREATE INDEX IF NOT EXISTS index_playlist_display_order_ownerKey_pinGroup_position ON playlist_display_order(ownerKey, pinGroup, position)",
        )
    }
}

val MIGRATION_10_11 = object : Migration(10, 11) {
    override fun migrate(db: SupportSQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE IF NOT EXISTS playback_media_cache (
                videoId TEXT NOT NULL PRIMARY KEY,
                cacheKey TEXT NOT NULL,
                itag INTEGER,
                lastPlayedAt INTEGER NOT NULL,
                historyOnlySince INTEGER
            )
            """.trimIndent(),
        )
    }
}
