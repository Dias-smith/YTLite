package com.ytlite.player.data.model

enum class DataSource(val dbValue: String) {
    LOCAL("LOCAL"),
    YOUTUBE("YOUTUBE"),
    ;

    companion object {
        fun fromDb(value: String): DataSource =
            entries.firstOrNull { it.dbValue == value } ?: LOCAL
    }
}

object PlaylistIds {
    const val YOUTUBE_PREFIX = "YT_PL_"

    fun youtube(youtubePlaylistId: String): String = "$YOUTUBE_PREFIX$youtubePlaylistId"

    fun stripYoutubePrefix(playlistId: String): String =
        playlistId.removePrefix(YOUTUBE_PREFIX)
}
