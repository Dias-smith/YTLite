package com.ytlite.player.data.repository

import com.ytlite.player.data.local.entity.TrackEntity
import com.ytlite.player.data.local.entity.UserTrackMetadataEntity
import com.ytlite.player.data.model.ResolvedTrackMetadata
import com.ytlite.player.data.model.TrackMetadataEdits
import com.ytlite.player.playback.NowPlaying
import com.ytlite.player.playback.QueueItem

object TrackMetadataResolver {

    fun resolve(
        canonical: TrackEntity,
        override: UserTrackMetadataEntity?,
    ): ResolvedTrackMetadata {
        val thumbnail = override?.customThumbnailUrl?.takeIf { it.isNotBlank() }
            ?: canonical.thumbnailHigh
            ?: canonical.thumbnailMedium
            ?: canonical.thumbnailLow
            ?: ""
        return ResolvedTrackMetadata(
            trackId = canonical.trackId,
            title = override?.customTitle?.takeIf { it.isNotBlank() } ?: canonical.title,
            artistName = override?.customArtistName?.takeIf { it.isNotBlank() }
                ?: canonical.primaryArtistName.orEmpty(),
            thumbnailUrl = thumbnail,
            album = override?.customAlbum?.takeIf { it.isNotBlank() },
            year = override?.customYear?.takeIf { it.isNotBlank() },
            hasUserOverride = override != null && override.hasAnyCustomField(),
        )
    }

    fun resolveForQueueItem(
        item: QueueItem,
        override: UserTrackMetadataEntity?,
    ): ResolvedTrackMetadata = ResolvedTrackMetadata(
        trackId = item.videoId,
        title = override?.customTitle?.takeIf { it.isNotBlank() } ?: item.title,
        artistName = override?.customArtistName?.takeIf { it.isNotBlank() } ?: item.channelName,
        thumbnailUrl = override?.customThumbnailUrl?.takeIf { it.isNotBlank() } ?: item.thumbnailUrl,
        album = override?.customAlbum?.takeIf { it.isNotBlank() } ?: item.album,
        year = override?.customYear?.takeIf { it.isNotBlank() } ?: item.year,
        hasUserOverride = override != null && override.hasAnyCustomField(),
    )

    fun resolveForNowPlaying(
        nowPlaying: NowPlaying,
        override: UserTrackMetadataEntity?,
    ): ResolvedTrackMetadata = ResolvedTrackMetadata(
        trackId = nowPlaying.videoId,
        title = override?.customTitle?.takeIf { it.isNotBlank() } ?: nowPlaying.title,
        artistName = override?.customArtistName?.takeIf { it.isNotBlank() } ?: nowPlaying.channelName,
        thumbnailUrl = override?.customThumbnailUrl?.takeIf { it.isNotBlank() } ?: nowPlaying.thumbnailUrl,
        album = override?.customAlbum?.takeIf { it.isNotBlank() },
        year = override?.customYear?.takeIf { it.isNotBlank() },
        hasUserOverride = override != null && override.hasAnyCustomField(),
    )

    fun editsDifferFromCanonical(
        canonical: TrackEntity,
        edits: TrackMetadataEdits,
    ): Boolean {
        val resolved = resolve(
            canonical = canonical,
            override = edits.toEntity(ownerKey = "", trackId = canonical.trackId, updatedAt = 0L),
        )
        val canonicalResolved = resolve(canonical, override = null)
        return resolved.title != canonicalResolved.title ||
            resolved.artistName != canonicalResolved.artistName ||
            resolved.thumbnailUrl != canonicalResolved.thumbnailUrl ||
            !edits.album.isNullOrBlank() ||
            !edits.year.isNullOrBlank()
    }

    private fun TrackMetadataEdits.toEntity(
        ownerKey: String,
        trackId: String,
        updatedAt: Long,
    ) = UserTrackMetadataEntity(
        ownerKey = ownerKey,
        trackId = trackId,
        customTitle = title,
        customArtistName = artistName,
        customThumbnailUrl = thumbnailUrl,
        customAlbum = album,
        customYear = year,
        updatedAt = updatedAt,
    )

    private fun UserTrackMetadataEntity.hasAnyCustomField(): Boolean =
        !customTitle.isNullOrBlank() ||
            !customArtistName.isNullOrBlank() ||
            !customThumbnailUrl.isNullOrBlank() ||
            !customAlbum.isNullOrBlank() ||
            !customYear.isNullOrBlank()
}
