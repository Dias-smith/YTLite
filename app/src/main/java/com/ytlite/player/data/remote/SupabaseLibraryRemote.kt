package com.ytlite.player.data.remote

import com.ytlite.player.data.auth.UserProfile
import com.ytlite.player.data.local.entity.ArtistEntity
import com.ytlite.player.data.local.entity.PlaybackHistoryEntity
import com.ytlite.player.data.local.entity.PlaylistEntity
import com.ytlite.player.data.local.entity.PlaylistTrackEntity
import com.ytlite.player.data.local.entity.TrackEntity
import com.ytlite.player.data.local.entity.UserSubscribedChannelEntity
import com.ytlite.player.data.local.entity.UserTrackLastPlayedEntity
import com.ytlite.player.data.local.entity.UserTrackMetadataEntity
import com.ytlite.player.data.remote.dto.ArtistDto
import com.ytlite.player.data.remote.dto.PlaybackHistoryDto
import com.ytlite.player.data.remote.dto.PlaylistDto
import com.ytlite.player.data.remote.dto.PlaylistTrackDto
import com.ytlite.player.data.remote.dto.ProfileDto
import com.ytlite.player.data.remote.dto.TrackDto
import com.ytlite.player.data.remote.dto.UserSubscribedChannelDto
import com.ytlite.player.data.remote.dto.UserTrackLastPlayedDto
import com.ytlite.player.data.remote.dto.UserTrackMetadataDto
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.Instant

class SupabaseLibraryRemote(
    private val client: SupabaseClient,
) {
    suspend fun fetchProfile(userId: String): UserProfile? = withContext(Dispatchers.IO) {
        runCatching {
            client.postgrest["profiles"]
                .select { filter { eq("id", userId) } }
                .decodeSingleOrNull<ProfileDto>()
                ?.toUserProfile()
        }.getOrNull()
    }

    suspend fun upsertProfile(profile: UserProfile) = withContext(Dispatchers.IO) {
        runCatching {
            client.postgrest["profiles"].upsert(
                ProfileDto(
                    id = profile.userId,
                    displayName = profile.displayName,
                    handle = profile.handle,
                    avatarUrl = profile.avatarUrl,
                ),
            )
        }
    }

    suspend fun upsertArtist(entity: ArtistEntity) = withContext(Dispatchers.IO) {
        runCatching {
            client.postgrest["artists"].upsert(entity.toDto())
        }
    }

    suspend fun upsertTrack(entity: TrackEntity) = withContext(Dispatchers.IO) {
        runCatching {
            client.postgrest["tracks"].upsert(entity.toDto())
        }
    }

    suspend fun fetchSystemPlaylist(userId: String, systemType: String): PlaylistDto? =
        withContext(Dispatchers.IO) {
            runCatching {
                client.postgrest["playlists"]
                    .select {
                        filter {
                            eq("user_id", userId)
                            eq("system_type", systemType)
                        }
                    }
                    .decodeSingleOrNull<PlaylistDto>()
            }.getOrNull()
        }

    suspend fun fetchAllPlaylists(userId: String): List<PlaylistDto> =
        withContext(Dispatchers.IO) {
            runCatching {
                client.postgrest["playlists"]
                    .select {
                        filter { eq("user_id", userId) }
                        order("updated_at", Order.DESCENDING)
                    }
                    .decodeList<PlaylistDto>()
            }.getOrDefault(emptyList())
        }

    suspend fun upsertPlaylist(dto: PlaylistDto) = withContext(Dispatchers.IO) {
        runCatching {
            client.postgrest["playlists"].upsert(dto)
        }
    }

    suspend fun upsertPlaylistTrack(dto: PlaylistTrackDto) = withContext(Dispatchers.IO) {
        runCatching {
            client.postgrest["playlist_track_cross_ref"].upsert(dto)
        }
    }

    suspend fun pullPlaylistTracks(playlistId: String): List<PlaylistTrackEntity> =
        withContext(Dispatchers.IO) {
            runCatching {
                client.postgrest["playlist_track_cross_ref"]
                    .select {
                        filter { eq("playlist_id", playlistId) }
                        order("position", Order.ASCENDING)
                    }
                    .decodeList<PlaylistTrackDto>()
                    .map { it.toEntity(playlistId) }
            }.getOrDefault(emptyList())
        }

    suspend fun deletePlaylist(playlistId: String) = withContext(Dispatchers.IO) {
        runCatching {
            client.postgrest["playlists"].delete {
                filter { eq("playlist_id", playlistId) }
            }
        }
    }

    suspend fun insertPlaybackHistory(userId: String, entity: PlaybackHistoryEntity) =
        withContext(Dispatchers.IO) {
            runCatching {
                client.postgrest["playback_history"].insert(
                    PlaybackHistoryDto(
                        historyId = entity.historyId,
                        userId = userId,
                        trackId = entity.trackId,
                        playedAt = Instant.ofEpochMilli(entity.playedAt).toString(),
                        progressMs = entity.progressMs,
                    ),
                )
            }
        }

    suspend fun upsertUserTrackLastPlayed(userId: String, entity: UserTrackLastPlayedEntity) =
        withContext(Dispatchers.IO) {
            runCatching {
                client.postgrest["user_track_last_played"].upsert(
                    UserTrackLastPlayedDto(
                        userId = userId,
                        trackId = entity.trackId,
                        lastPlayedAt = Instant.ofEpochMilli(entity.lastPlayedAt).toString(),
                        progressMs = entity.progressMs,
                    ),
                )
            }
        }

    suspend fun pullUserTrackLastPlayed(userId: String): List<UserTrackLastPlayedEntity> =
        withContext(Dispatchers.IO) {
            runCatching {
                client.postgrest["user_track_last_played"]
                    .select {
                        filter { eq("user_id", userId) }
                        order("last_played_at", Order.DESCENDING)
                    }
                    .decodeList<UserTrackLastPlayedDto>()
                    .map { it.toEntity("user:$userId") }
            }.getOrDefault(emptyList())
        }

    suspend fun pullTracksByIds(trackIds: List<String>): List<TrackEntity> =
        withContext(Dispatchers.IO) {
            if (trackIds.isEmpty()) return@withContext emptyList()
            runCatching {
                client.postgrest["tracks"]
                    .select { filter { isIn("track_id", trackIds) } }
                    .decodeList<TrackDto>()
                    .map { it.toEntity() }
            }.getOrDefault(emptyList())
        }

    suspend fun pullSystemPlaylistTracks(
        userId: String,
        systemType: String,
    ): List<PlaylistTrackEntity> = withContext(Dispatchers.IO) {
        val playlist = fetchSystemPlaylist(userId, systemType) ?: return@withContext emptyList()
        runCatching {
            client.postgrest["playlist_track_cross_ref"]
                .select {
                    filter { eq("playlist_id", playlist.playlistId) }
                    order("position", Order.ASCENDING)
                }
                .decodeList<PlaylistTrackDto>()
                .map { it.toEntity(playlist.playlistId) }
        }.getOrDefault(emptyList())
    }

    suspend fun upsertUserTrackMetadata(userId: String, entity: UserTrackMetadataEntity) =
        withContext(Dispatchers.IO) {
            runCatching {
                client.postgrest["user_track_metadata"].upsert(entity.toDto(userId))
            }
        }

    suspend fun pullUserTrackMetadata(userId: String): List<UserTrackMetadataDto> =
        withContext(Dispatchers.IO) {
            runCatching {
                client.postgrest["user_track_metadata"]
                    .select { filter { eq("user_id", userId) } }
                    .decodeList<UserTrackMetadataDto>()
            }.getOrDefault(emptyList())
        }

    suspend fun deleteUserTrackMetadata(userId: String, trackId: String) =
        withContext(Dispatchers.IO) {
            runCatching {
                client.postgrest["user_track_metadata"].delete {
                    filter {
                        eq("user_id", userId)
                        eq("track_id", trackId)
                    }
                }
            }
        }

    suspend fun upsertUserSubscribedChannel(userId: String, entity: UserSubscribedChannelEntity) =
        withContext(Dispatchers.IO) {
            runCatching {
                client.postgrest["user_subscribed_channels"].upsert(entity.toDto(userId))
            }
        }

    suspend fun pullUserSubscribedChannels(userId: String): List<UserSubscribedChannelDto> =
        withContext(Dispatchers.IO) {
            runCatching {
                client.postgrest["user_subscribed_channels"]
                    .select { filter { eq("user_id", userId) } }
                    .decodeList<UserSubscribedChannelDto>()
            }.getOrDefault(emptyList())
        }

    suspend fun deleteUserSubscribedChannel(userId: String, channelId: String) =
        withContext(Dispatchers.IO) {
            runCatching {
                client.postgrest["user_subscribed_channels"].delete {
                    filter {
                        eq("user_id", userId)
                        eq("channel_id", channelId)
                    }
                }
            }
        }

    private fun ProfileDto.toUserProfile() = UserProfile(
        userId = id,
        displayName = displayName.ifBlank { "User" },
        handle = handle,
        avatarUrl = avatarUrl,
    )

    private fun ArtistEntity.toDto() = ArtistDto(
        artistId = artistId,
        name = name,
        avatarUrl = avatarUrl,
        bannerUrl = bannerUrl,
        subscriberCount = subscriberCount,
        subscriberCountText = subscriberCountText,
        description = description,
    )

    private fun TrackEntity.toDto() = TrackDto(
        trackId = trackId,
        title = title,
        durationSeconds = durationSeconds,
        durationText = durationText,
        thumbnailLow = thumbnailLow,
        thumbnailMedium = thumbnailMedium,
        thumbnailHigh = thumbnailHigh,
        viewCount = viewCount,
        viewCountText = viewCountText,
        publishedText = publishedText,
        primaryArtistId = primaryArtistId,
        primaryArtistName = primaryArtistName,
    )

    private fun TrackDto.toEntity() = TrackEntity(
        trackId = trackId,
        title = title,
        durationSeconds = durationSeconds,
        durationText = durationText,
        thumbnailLow = thumbnailLow,
        thumbnailMedium = thumbnailMedium,
        thumbnailHigh = thumbnailHigh,
        viewCount = viewCount,
        viewCountText = viewCountText,
        publishedText = publishedText,
        primaryArtistId = primaryArtistId,
        primaryArtistName = primaryArtistName,
    )

    private fun PlaylistTrackDto.toEntity(playlistId: String) = PlaylistTrackEntity(
        playlistId = playlistId,
        trackId = trackId,
        position = position,
        createdAt = createdAt?.let {
            runCatching { Instant.parse(it).toEpochMilli() }.getOrDefault(System.currentTimeMillis())
        } ?: System.currentTimeMillis(),
        isSynced = true,
    )

    private fun UserTrackLastPlayedDto.toEntity(ownerKey: String) = UserTrackLastPlayedEntity(
        ownerKey = ownerKey,
        trackId = trackId,
        lastPlayedAt = runCatching { Instant.parse(lastPlayedAt).toEpochMilli() }
            .getOrDefault(System.currentTimeMillis()),
        progressMs = progressMs,
        isSynced = true,
    )

    private fun UserTrackMetadataEntity.toDto(userId: String) = UserTrackMetadataDto(
        userId = userId,
        trackId = trackId,
        customTitle = customTitle,
        customArtistName = customArtistName,
        customThumbnailUrl = customThumbnailUrl,
        customAlbum = customAlbum,
        customYear = customYear,
        updatedAt = Instant.ofEpochMilli(updatedAt).toString(),
    )

    private fun UserSubscribedChannelEntity.toDto(userId: String) = UserSubscribedChannelDto(
        userId = userId,
        channelId = channelId,
        title = title,
        handle = handle,
        avatarUrl = avatarUrl,
        subscriberCountText = subscriberCountText,
        description = description,
        subscribedAt = Instant.ofEpochMilli(subscribedAt).toString(),
        updatedAt = Instant.ofEpochMilli(subscribedAt).toString(),
    )
}

fun UserTrackMetadataDto.updatedAtMillis(): Long =
    runCatching { Instant.parse(updatedAt).toEpochMilli() }.getOrDefault(0L)

fun UserTrackMetadataDto.toEntity(ownerKey: String) = UserTrackMetadataEntity(
    ownerKey = ownerKey,
    trackId = trackId,
    customTitle = customTitle,
    customArtistName = customArtistName,
    customThumbnailUrl = customThumbnailUrl,
    customAlbum = customAlbum,
    customYear = customYear,
    updatedAt = updatedAtMillis(),
    isSynced = true,
)

fun UserSubscribedChannelDto.subscribedAtMillis(): Long =
    runCatching { Instant.parse(subscribedAt).toEpochMilli() }.getOrDefault(0L)

fun UserSubscribedChannelDto.toEntity(ownerKey: String) = UserSubscribedChannelEntity(
    ownerKey = ownerKey,
    channelId = channelId,
    title = title,
    handle = handle,
    avatarUrl = avatarUrl,
    subscriberCountText = subscriberCountText,
    description = description,
    subscribedAt = subscribedAtMillis(),
    isSynced = true,
)
