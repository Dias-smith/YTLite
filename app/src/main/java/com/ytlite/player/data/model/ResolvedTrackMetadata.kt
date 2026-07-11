package com.ytlite.player.data.model

import androidx.compose.runtime.Immutable

@Immutable
data class ResolvedTrackMetadata(
    val trackId: String,
    val title: String,
    val artistName: String,
    val thumbnailUrl: String,
    val album: String? = null,
    val year: String? = null,
    val hasUserOverride: Boolean = false,
) {
    fun subtitleLine(): String = listOfNotNull(
        artistName.takeIf { it.isNotBlank() },
        album?.takeIf { it.isNotBlank() },
        year?.takeIf { it.isNotBlank() },
    ).joinToString(" · ")
}
