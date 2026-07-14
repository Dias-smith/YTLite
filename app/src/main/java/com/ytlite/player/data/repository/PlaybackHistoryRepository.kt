package com.ytlite.player.data.repository

import com.ytlite.player.data.local.YTLiteDatabase
import com.ytlite.player.data.local.entity.ArtistEntity
import com.ytlite.player.data.local.entity.PlaybackHistoryEntity
import com.ytlite.player.data.local.entity.TrackEntity
import com.ytlite.player.data.local.entity.UserTrackLastPlayedEntity
import com.ytlite.player.data.model.LibraryVideo
import com.ytlite.player.data.remote.SupabaseLibraryRemote
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.UUID

class PlaybackHistoryRepository(
    private val database: YTLiteDatabase,
    private val remote: SupabaseLibraryRemote?,
) {
    private val artistDao = database.artistDao()
    private val trackDao = database.trackDao()
    private val playbackHistoryDao = database.playbackHistoryDao()
    private val userTrackLastPlayedDao = database.userTrackLastPlayedDao()

    suspend fun depositPlayback(
        ownerKey: String,
        trackId: String,
        title: String,
        durationSeconds: Int = 0,
        thumbnailUrl: String,
        channelId: String? = null,
        channelName: String? = null,
        progressMs: Long = 0L,
        userId: String? = null,
    ) = withContext(Dispatchers.IO) {
        val now = System.currentTimeMillis()
        if (!channelName.isNullOrBlank()) {
            val artistId = LibraryItemMapper.artistKey(
                channelId = channelId,
                channelName = channelName,
            )
            artistDao.upsert(
                ArtistEntity(
                    artistId = artistId,
                    name = channelName.trim(),
                ),
            )
        }
        val existing = trackDao.getById(trackId)
        trackDao.upsert(
            mergeCanonicalTrack(
                existing = existing,
                trackId = trackId,
                title = title,
                durationSeconds = durationSeconds,
                thumbnailUrl = thumbnailUrl,
                channelId = channelId,
                channelName = channelName,
            ),
        )
        val historyId = UUID.randomUUID().toString()
        playbackHistoryDao.insert(
            PlaybackHistoryEntity(
                historyId = historyId,
                ownerKey = ownerKey,
                trackId = trackId,
                playedAt = now,
                progressMs = progressMs,
            ),
        )
        userTrackLastPlayedDao.upsert(
            UserTrackLastPlayedEntity(
                ownerKey = ownerKey,
                trackId = trackId,
                lastPlayedAt = now,
                progressMs = progressMs,
            ),
        )
        if (userId != null) {
            syncToRemote(userId, ownerKey, trackId, historyId, now, progressMs)
        }
    }

    suspend fun depositPlayback(
        video: LibraryVideo,
        ownerKey: String,
        progressMs: Long = 0L,
        userId: String? = null,
    ) = depositPlayback(
        ownerKey = ownerKey,
        trackId = video.videoId,
        title = video.title,
        durationSeconds = 0,
        thumbnailUrl = video.thumbnailUrl,
        channelId = video.channelId,
        channelName = video.channelName,
        progressMs = progressMs,
        userId = userId,
    )

    suspend fun updateProgress(
        ownerKey: String,
        trackId: String,
        progressMs: Long,
    ) = withContext(Dispatchers.IO) {
        val existing = userTrackLastPlayedDao.getAllByOwner(ownerKey)
            .firstOrNull { it.trackId == trackId }
            ?: return@withContext
        userTrackLastPlayedDao.upsert(
            existing.copy(
                progressMs = progressMs,
                lastPlayedAt = System.currentTimeMillis(),
            ),
        )
    }

    private fun mergeCanonicalTrack(
        existing: TrackEntity?,
        trackId: String,
        title: String,
        durationSeconds: Int,
        thumbnailUrl: String,
        channelId: String?,
        channelName: String?,
    ): TrackEntity = TrackEntity(
        trackId = trackId,
        title = title.takeIf { it.isNotBlank() } ?: existing?.title.orEmpty(),
        durationSeconds = durationSeconds.takeIf { it > 0 } ?: existing?.durationSeconds ?: 0,
        durationText = existing?.durationText,
        thumbnailLow = existing?.thumbnailLow,
        thumbnailMedium = existing?.thumbnailMedium,
        thumbnailHigh = thumbnailUrl.takeIf { it.isNotBlank() }
            ?: existing?.thumbnailHigh,
        viewCount = existing?.viewCount ?: 0L,
        viewCountText = existing?.viewCountText,
        publishedText = existing?.publishedText,
        primaryArtistId = channelId?.takeIf { it.isNotBlank() } ?: existing?.primaryArtistId,
        primaryArtistName = channelName?.takeIf { it.isNotBlank() } ?: existing?.primaryArtistName,
    )

    private suspend fun syncToRemote(
        userId: String,
        ownerKey: String,
        trackId: String,
        historyId: String,
        playedAt: Long,
        progressMs: Long,
    ) {
        val remoteClient = remote ?: return
        val track = trackDao.getById(trackId) ?: return
        track.primaryArtistId?.let { artistId ->
            artistDao.getById(artistId)?.let { remoteClient.upsertArtist(it) }
        }
        remoteClient.upsertTrack(track)
        remoteClient.insertPlaybackHistory(
            userId,
            PlaybackHistoryEntity(
                historyId = historyId,
                ownerKey = ownerKey,
                trackId = trackId,
                playedAt = playedAt,
                progressMs = progressMs,
            ),
        )
        playbackHistoryDao.markSynced(historyId)
        userTrackLastPlayedDao.getAllByOwner(ownerKey)
            .firstOrNull { it.trackId == trackId }
            ?.let { remoteClient.upsertUserTrackLastPlayed(userId, it) }
    }
}
