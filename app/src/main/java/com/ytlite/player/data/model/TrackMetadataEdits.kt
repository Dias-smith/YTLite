package com.ytlite.player.data.model

import androidx.compose.runtime.Immutable

@Immutable
data class TrackMetadataEdits(
    val title: String? = null,
    val artistName: String? = null,
    val thumbnailUrl: String? = null,
    val album: String? = null,
    val year: String? = null,
) {
    companion object {
        fun fromForm(
            title: String,
            artistName: String,
            thumbnailUrl: String,
            album: String,
            year: String,
        ): TrackMetadataEdits = TrackMetadataEdits(
            title = title.trim().ifBlank { null },
            artistName = artistName.trim().ifBlank { null },
            thumbnailUrl = thumbnailUrl.trim().ifBlank { null },
            album = album.trim().ifBlank { null },
            year = year.trim().ifBlank { null },
        )
    }

    fun isEmpty(): Boolean =
        title == null &&
            artistName == null &&
            thumbnailUrl == null &&
            album == null &&
            year == null
}
