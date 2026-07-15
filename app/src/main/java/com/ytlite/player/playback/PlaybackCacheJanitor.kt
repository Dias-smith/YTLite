package com.ytlite.player.playback

import android.content.Context
import android.util.Log
import com.ytlite.player.data.local.YTLiteDatabase
import com.ytlite.player.data.local.entity.PlaybackCacheEntity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Local-only janitor: keep cache while track is in any playlist (History is virtual and not in
 * cross-ref). History-only entries are purged after [PlaybackCachePolicy.HistoryOnlyRetentionMs].
 */
object PlaybackCacheJanitor {
    private const val TAG = "PlaybackCacheJanitor"

    suspend fun recordPlay(
        context: Context,
        videoId: String,
        cacheKey: String,
        itag: Int?,
        ownerKey: String?,
    ) = withContext(Dispatchers.IO) {
        val database = YTLiteDatabase.getInstance(context)
        val keep = ownerKey != null &&
            database.playlistTrackDao().isTrackInAnyPlaylist(ownerKey, videoId)
        val now = System.currentTimeMillis()
        database.playbackCacheDao().upsert(
            PlaybackCacheEntity(
                videoId = videoId,
                cacheKey = cacheKey,
                itag = itag,
                lastPlayedAt = now,
                historyOnlySince = if (keep) null else now,
            ),
        )
    }

    suspend fun evaluateTrack(
        context: Context,
        ownerKey: String,
        videoId: String,
    ) = withContext(Dispatchers.IO) {
        val database = YTLiteDatabase.getInstance(context)
        val cacheDao = database.playbackCacheDao()
        val entity = cacheDao.get(videoId) ?: return@withContext
        val inPlaylist = database.playlistTrackDao().isTrackInAnyPlaylist(ownerKey, videoId)
        val now = System.currentTimeMillis()
        if (inPlaylist) {
            if (entity.historyOnlySince != null) {
                cacheDao.updateHistoryOnlySince(videoId, null)
            }
            return@withContext
        }
        val since = entity.historyOnlySince ?: run {
            cacheDao.updateHistoryOnlySince(videoId, now)
            now
        }
        if (now - since >= PlaybackCachePolicy.HistoryOnlyRetentionMs) {
            purge(context, entity)
        }
    }

    suspend fun purgeExpired(context: Context, ownerKey: String?) = withContext(Dispatchers.IO) {
        val database = YTLiteDatabase.getInstance(context)
        val cacheDao = database.playbackCacheDao()
        val playlistTrackDao = database.playlistTrackDao()
        val now = System.currentTimeMillis()
        cacheDao.getAll().forEach { entity ->
            val inPlaylist = ownerKey != null &&
                playlistTrackDao.isTrackInAnyPlaylist(ownerKey, entity.videoId)
            if (inPlaylist) {
                if (entity.historyOnlySince != null) {
                    cacheDao.updateHistoryOnlySince(entity.videoId, null)
                }
                return@forEach
            }
            val since = entity.historyOnlySince
            if (since == null) {
                cacheDao.updateHistoryOnlySince(entity.videoId, now)
            } else if (now - since >= PlaybackCachePolicy.HistoryOnlyRetentionMs) {
                purge(context, entity)
            }
        }
    }

    suspend fun purgeVideo(context: Context, videoId: String) = withContext(Dispatchers.IO) {
        val entity = YTLiteDatabase.getInstance(context).playbackCacheDao().get(videoId)
            ?: return@withContext
        purge(context, entity)
    }

    private suspend fun purge(context: Context, entity: PlaybackCacheEntity) {
        Log.d(TAG, "Purging media cache videoId=${entity.videoId} key=${entity.cacheKey}")
        PlaybackMediaCache.removeResource(context, entity.cacheKey)
        if (entity.cacheKey != entity.videoId) {
            PlaybackMediaCache.removeResource(context, entity.videoId)
        }
        YTLiteDatabase.getInstance(context).playbackCacheDao().delete(entity.videoId)
    }
}
