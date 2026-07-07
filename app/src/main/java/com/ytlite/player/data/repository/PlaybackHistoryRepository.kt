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
        if (!channelId.isNullOrBlank() && !channelName.isNullOrBlank()) {
            artistDao.upsert(ArtistEntity(artistId = channelId, name = channelName))
        }
        trackDao.upsert(
            TrackEntity(
                trackId = trackId,
                title = title,
                durationSeconds = durationSeconds,
                thumbnailHigh = thumbnailUrl,
                primaryArtistId = channelId,
                primaryArtistName = channelName,
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
