package com.ytlite.player.data.remote.dto

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ProfileDto(
    val id: String,
    @SerialName("display_name") val displayName: String = "",
    val handle: String? = null,
    @SerialName("avatar_url") val avatarUrl: String? = null,
)

@Serializable
data class ArtistDto(
    @SerialName("artist_id") val artistId: String,
    val name: String,
    @SerialName("avatar_url") val avatarUrl: String? = null,
    @SerialName("banner_url") val bannerUrl: String? = null,
    @SerialName("subscriber_count") val subscriberCount: Long? = null,
    @SerialName("subscriber_count_text") val subscriberCountText: String? = null,
    val description: String? = null,
)

@Serializable
data class TrackDto(
    @SerialName("track_id") val trackId: String,
    val title: String,
    @SerialName("duration_seconds") val durationSeconds: Int = 0,
    @SerialName("duration_text") val durationText: String? = null,
    @SerialName("thumbnail_low") val thumbnailLow: String? = null,
    @SerialName("thumbnail_medium") val thumbnailMedium: String? = null,
    @SerialName("thumbnail_high") val thumbnailHigh: String? = null,
    @SerialName("view_count") val viewCount: Long = 0L,
    @SerialName("view_count_text") val viewCountText: String? = null,
    @SerialName("published_text") val publishedText: String? = null,
    @SerialName("primary_artist_id") val primaryArtistId: String? = null,
    @SerialName("primary_artist_name") val primaryArtistName: String? = null,
)

@Serializable
data class PlaylistDto(
    @SerialName("playlist_id") val playlistId: String,
    @SerialName("user_id") val userId: String,
    val name: String,
    @SerialName("cover_url_or_path") val coverUrlOrPath: String? = null,
    val description: String? = null,
    @SerialName("system_type") val systemType: String? = null,
)

@Serializable
data class PlaylistTrackDto(
    @SerialName("playlist_id") val playlistId: String,
    @SerialName("track_id") val trackId: String,
    val position: Int = 0,
    @SerialName("created_at") val createdAt: String? = null,
)

@Serializable
data class PlaybackHistoryDto(
    @SerialName("history_id") val historyId: String? = null,
    @SerialName("user_id") val userId: String,
    @SerialName("track_id") val trackId: String,
    @SerialName("played_at") val playedAt: String,
    @SerialName("progress_ms") val progressMs: Long = 0L,
)

@Serializable
data class UserTrackMetadataDto(
    @SerialName("user_id") val userId: String,
    @SerialName("track_id") val trackId: String,
    @SerialName("custom_title") val customTitle: String? = null,
    @SerialName("custom_artist_name") val customArtistName: String? = null,
    @SerialName("custom_thumbnail_url") val customThumbnailUrl: String? = null,
    @SerialName("custom_album") val customAlbum: String? = null,
    @SerialName("custom_year") val customYear: String? = null,
    @SerialName("updated_at") val updatedAt: String,
)

@Serializable
data class UserTrackLastPlayedDto(
    @SerialName("user_id") val userId: String,
    @SerialName("track_id") val trackId: String,
    @SerialName("last_played_at") val lastPlayedAt: String,
    @SerialName("progress_ms") val progressMs: Long = 0L,
)
