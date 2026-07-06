package com.ytlite.player.data.repository

import android.content.Context
import com.ytlite.player.data.auth.AuthRepository
import com.ytlite.player.data.auth.SupabaseClientProvider
import com.ytlite.player.data.auth.UserProfile
import com.ytlite.player.data.auth.UserSession
import com.ytlite.player.data.local.YTLiteDatabase
import com.ytlite.player.data.local.entity.ArtistEntity
import com.ytlite.player.data.local.entity.PlaybackHistoryEntity
import com.ytlite.player.data.local.entity.PlaylistEntity
import com.ytlite.player.data.local.entity.PlaylistSystemType
import com.ytlite.player.data.local.entity.PlaylistTrackEntity
import com.ytlite.player.data.local.entity.TrackEntity
import com.ytlite.player.data.local.entity.UserTrackLastPlayedEntity
import com.ytlite.player.data.local.model.LibraryVideoRow
import com.ytlite.player.data.model.LibraryVideo
import com.ytlite.player.data.remote.SupabaseLibraryRemote
import com.ytlite.player.data.remote.dto.PlaylistDto
import com.ytlite.player.data.remote.dto.PlaylistTrackDto
import com.ytlite.player.playback.NowPlaying
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

class LibraryRepository(
    context: Context,
    private val authRepository: AuthRepository,
) {
    private val appContext = context.applicationContext
    private val database = YTLiteDatabase.getInstance(appContext)
    private val artistDao = database.artistDao()
    private val trackDao = database.trackDao()
    private val playlistDao = database.playlistDao()
    private val playlistTrackDao = database.playlistTrackDao()
    private val playbackHistoryDao = database.playbackHistoryDao()
    private val userTrackLastPlayedDao = database.userTrackLastPlayedDao()

    private val remote: SupabaseLibraryRemote? =
        SupabaseClientProvider.get(appContext)?.let { SupabaseLibraryRemote(it) }

    private val systemPlaylistsEnsured = ConcurrentHashMap.newKeySet<String>()

    init {
        authRepository.onMergeGuestData = { guestOwnerKey, userId, profile ->
            mergeGuestDataIntoUser(guestOwnerKey, userId, profile)
        }
    }

    fun observeHistory(ownerKey: String, limit: Int = 20): Flow<List<LibraryVideo>> =
        userTrackLastPlayedDao.observeHistoryRows(ownerKey, limit).map { rows ->
            rows.map { it.toLibraryVideo() }
        }

    fun observeLikedCount(ownerKey: String): Flow<Int> =
        playlistTrackDao.observeSystemPlaylistCount(ownerKey, PlaylistSystemType.FAVORITES)

    fun observeWatchLaterCount(ownerKey: String): Flow<Int> =
        playlistTrackDao.observeSystemPlaylistCount(ownerKey, PlaylistSystemType.WATCH_LATER)

    suspend fun addToHistory(
        video: LibraryVideo,
        ownerKey: String,
        progressMs: Long = 0L,
    ) = withContext(Dispatchers.IO) {
        val now = System.currentTimeMillis()
        upsertCatalogFromVideo(video)
        ensureSystemPlaylists(ownerKey)

        val historyId = UUID.randomUUID().toString()
        playbackHistoryDao.insert(
            PlaybackHistoryEntity(
                historyId = historyId,
                ownerKey = ownerKey,
                trackId = video.videoId,
                playedAt = now,
                progressMs = progressMs,
            ),
        )
        userTrackLastPlayedDao.upsert(
            UserTrackLastPlayedEntity(
                ownerKey = ownerKey,
                trackId = video.videoId,
                lastPlayedAt = now,
                progressMs = progressMs,
            ),
        )

        val userId = (authRepository.currentSession() as? UserSession.Authenticated)?.profile?.userId
        if (userId != null) {
            syncHistoryToRemote(userId, ownerKey, video.videoId, historyId, now, progressMs)
        }
    }

    suspend fun addToHistory(nowPlaying: NowPlaying) {
        val ownerKey = authRepository.currentSession()?.ownerKey ?: return
        addToHistory(
            LibraryVideo(
                videoId = nowPlaying.videoId,
                title = nowPlaying.title,
                channelName = nowPlaying.channelName,
                thumbnailUrl = nowPlaying.thumbnailUrl,
            ),
            ownerKey = ownerKey,
        )
    }

    suspend fun mergeGuestDataIntoUser(
        guestOwnerKey: String,
        userId: String,
        profile: UserProfile,
    ) = withContext(Dispatchers.IO) {
        val userOwnerKey = "user:$userId"

        ensureSystemPlaylists(guestOwnerKey)
        ensureSystemPlaylists(userOwnerKey, userId)

        val guestFavorites = playlistDao.getSystemPlaylist(guestOwnerKey, PlaylistSystemType.FAVORITES)
        val guestWatchLater = playlistDao.getSystemPlaylist(guestOwnerKey, PlaylistSystemType.WATCH_LATER)
        val userFavorites = playlistDao.getSystemPlaylist(userOwnerKey, PlaylistSystemType.FAVORITES)
        val userWatchLater = playlistDao.getSystemPlaylist(userOwnerKey, PlaylistSystemType.WATCH_LATER)

        if (guestFavorites != null && userFavorites != null) {
            mergePlaylistTracks(guestFavorites.playlistId, userFavorites.playlistId)
        }
        if (guestWatchLater != null && userWatchLater != null) {
            mergePlaylistTracks(guestWatchLater.playlistId, userWatchLater.playlistId)
        }

        userTrackLastPlayedDao.migrateOwnerKey(guestOwnerKey, userOwnerKey)
        playbackHistoryDao.migrateOwnerKey(guestOwnerKey, userOwnerKey)

        val guestPlaylists = playlistDao.getAllByOwner(guestOwnerKey)
            .filter { it.systemType == null }
        guestPlaylists.forEach { guestPlaylist ->
            val migrated = guestPlaylist.copy(
                ownerKey = userOwnerKey,
                userId = userId,
                isSynced = false,
            )
            playlistDao.upsert(migrated)
            playlistTrackDao.migratePlaylistId(guestPlaylist.playlistId, migrated.playlistId)
        }

        playlistDao.getAllByOwner(guestOwnerKey)
            .filter { it.systemType != null }
            .forEach { playlistDao.upsert(it.copy(ownerKey = userOwnerKey, userId = userId)) }

        uploadLocalDataToRemote(userId, userOwnerKey)
        remote?.upsertProfile(profile)
        pullRemoteIntoLocal(userId, userOwnerKey)
    }

    suspend fun pullRemoteIntoLocal(userId: String, userOwnerKey: String) = withContext(Dispatchers.IO) {
        val remoteClient = remote ?: return@withContext

        val remoteLastPlayed = remoteClient.pullUserTrackLastPlayed(userId)
        val trackIds = remoteLastPlayed.map { it.trackId }.distinct()
        val remoteTracks = remoteClient.pullTracksByIds(trackIds)
        remoteTracks.forEach { trackDao.upsert(it) }

        remoteLastPlayed.forEach { remoteEntity ->
            val local = userTrackLastPlayedDao.getAllByOwner(userOwnerKey)
                .firstOrNull { it.trackId == remoteEntity.trackId }
            if (local == null || remoteEntity.lastPlayedAt >= local.lastPlayedAt) {
                userTrackLastPlayedDao.upsert(remoteEntity.copy(ownerKey = userOwnerKey))
            }
        }

        syncSystemPlaylistFromRemote(userId, userOwnerKey, PlaylistSystemType.FAVORITES)
        syncSystemPlaylistFromRemote(userId, userOwnerKey, PlaylistSystemType.WATCH_LATER)

        remoteClient.fetchProfile(userId)?.let { authRepository.updateAuthenticatedProfile(it) }
    }

    private suspend fun upsertCatalogFromVideo(video: LibraryVideo) {
        if (!video.channelId.isNullOrBlank()) {
            artistDao.upsert(
                ArtistEntity(
                    artistId = video.channelId,
                    name = video.channelName,
                ),
            )
        }
        trackDao.upsert(
            TrackEntity(
                trackId = video.videoId,
                title = video.title,
                durationText = video.durationText,
                thumbnailHigh = video.thumbnailUrl,
                viewCountText = video.viewCountText,
                publishedText = video.publishedTimeText,
                primaryArtistId = video.channelId,
                primaryArtistName = video.channelName,
            ),
        )
    }

    private suspend fun ensureSystemPlaylists(ownerKey: String, userId: String? = null) {
        if (systemPlaylistsEnsured.contains(ownerKey)) return
        val favorites = playlistDao.getSystemPlaylist(ownerKey, PlaylistSystemType.FAVORITES)
        val watchLater = playlistDao.getSystemPlaylist(ownerKey, PlaylistSystemType.WATCH_LATER)
        if (favorites != null && watchLater != null) {
            systemPlaylistsEnsured.add(ownerKey)
            return
        }
        ensureSystemPlaylist(ownerKey, userId, PlaylistSystemType.FAVORITES, "Liked videos")
        ensureSystemPlaylist(ownerKey, userId, PlaylistSystemType.WATCH_LATER, "Watch later")
        systemPlaylistsEnsured.add(ownerKey)
    }

    private suspend fun ensureSystemPlaylist(
        ownerKey: String,
        userId: String?,
        systemType: String,
        name: String,
    ) {
        val existing = playlistDao.getSystemPlaylist(ownerKey, systemType)
        if (existing != null) return

        val playlistId = if (userId != null) {
            remote?.fetchSystemPlaylist(userId, systemType)?.playlistId
        } else {
            null
        } ?: UUID.randomUUID().toString()

        playlistDao.upsert(
            PlaylistEntity(
                playlistId = playlistId,
                ownerKey = ownerKey,
                userId = userId,
                name = name,
                systemType = systemType,
                isSynced = userId != null,
            ),
        )
    }

    private suspend fun mergePlaylistTracks(fromPlaylistId: String, toPlaylistId: String) {
        val fromTracks = playlistTrackDao.getAllByPlaylist(fromPlaylistId)
        val toTracks = playlistTrackDao.getAllByPlaylist(toPlaylistId)
        val existingTrackIds = toTracks.map { it.trackId }.toSet()
        var nextPosition = (toTracks.maxOfOrNull { it.position } ?: -1) + 1

        fromTracks.forEach { track ->
            if (track.trackId !in existingTrackIds) {
                playlistTrackDao.upsert(
                    track.copy(
                        playlistId = toPlaylistId,
                        position = nextPosition++,
                        isSynced = false,
                    ),
                )
            }
        }
    }

    private suspend fun syncHistoryToRemote(
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
        val historyEntity = PlaybackHistoryEntity(
            historyId = historyId,
            ownerKey = ownerKey,
            trackId = trackId,
            playedAt = playedAt,
            progressMs = progressMs,
        )
        remoteClient.insertPlaybackHistory(userId, historyEntity)
        playbackHistoryDao.markSynced(historyId)
        userTrackLastPlayedDao.getAllByOwner(ownerKey)
            .firstOrNull { it.trackId == trackId }
            ?.let { remoteClient.upsertUserTrackLastPlayed(userId, it) }
    }

    private suspend fun uploadLocalDataToRemote(userId: String, userOwnerKey: String) {
        val remoteClient = remote ?: return

        userTrackLastPlayedDao.getAllByOwner(userOwnerKey).forEach { entry ->
            trackDao.getById(entry.trackId)?.let { track ->
                track.primaryArtistId?.let { artistId ->
                    artistDao.getById(artistId)?.let { remoteClient.upsertArtist(it) }
                }
                remoteClient.upsertTrack(track)
                remoteClient.upsertUserTrackLastPlayed(userId, entry)
            }
        }

        playbackHistoryDao.getUnsyncedByOwner(userOwnerKey).forEach { history ->
            trackDao.getById(history.trackId)?.let { remoteClient.upsertTrack(it) }
            remoteClient.insertPlaybackHistory(userId, history)
            playbackHistoryDao.markSynced(history.historyId)
        }

        listOf(PlaylistSystemType.FAVORITES, PlaylistSystemType.WATCH_LATER).forEach { systemType ->
            val playlist = playlistDao.getSystemPlaylist(userOwnerKey, systemType) ?: return@forEach
            remoteClient.upsertPlaylist(
                PlaylistDto(
                    playlistId = playlist.playlistId,
                    userId = userId,
                    name = playlist.name,
                    coverUrlOrPath = playlist.coverUrlOrPath,
                    description = playlist.description,
                    systemType = playlist.systemType,
                ),
            )
            playlistTrackDao.getAllByPlaylist(playlist.playlistId).forEach { trackRef ->
                trackDao.getById(trackRef.trackId)?.let { remoteClient.upsertTrack(it) }
                remoteClient.upsertPlaylistTrack(
                    PlaylistTrackDto(
                        playlistId = playlist.playlistId,
                        trackId = trackRef.trackId,
                        position = trackRef.position,
                        createdAt = null,
                    ),
                )
            }
        }
    }

    private suspend fun syncSystemPlaylistFromRemote(
        userId: String,
        userOwnerKey: String,
        systemType: String,
    ) {
        val remoteClient = remote ?: return
        val remotePlaylist = remoteClient.fetchSystemPlaylist(userId, systemType) ?: return
        val localPlaylist = playlistDao.getSystemPlaylist(userOwnerKey, systemType)
        val playlistId = remotePlaylist.playlistId

        playlistDao.upsert(
            PlaylistEntity(
                playlistId = playlistId,
                ownerKey = userOwnerKey,
                userId = userId,
                name = remotePlaylist.name,
                coverUrlOrPath = remotePlaylist.coverUrlOrPath,
                description = remotePlaylist.description,
                systemType = remotePlaylist.systemType,
                isSynced = true,
            ),
        )

        if (localPlaylist != null && localPlaylist.playlistId != playlistId) {
            mergePlaylistTracks(localPlaylist.playlistId, playlistId)
        }

        val remoteTracks = remoteClient.pullSystemPlaylistTracks(userId, systemType)
        val trackIds = remoteTracks.map { it.trackId }.distinct()
        remoteClient.pullTracksByIds(trackIds).forEach { trackDao.upsert(it) }
        remoteTracks.forEach { playlistTrackDao.upsert(it.copy(playlistId = playlistId)) }
    }

    private fun LibraryVideoRow.toLibraryVideo() = LibraryVideo(
        videoId = trackId,
        title = title,
        channelName = primaryArtistName.orEmpty(),
        channelId = primaryArtistId,
        thumbnailUrl = thumbnailUrl,
        durationText = durationText,
        viewCountText = viewCountText,
        publishedTimeText = publishedText,
        watchedAt = lastPlayedAt,
        progressMs = progressMs,
    )

    companion object {
        @Volatile
        private var instance: LibraryRepository? = null

        fun getInstance(context: Context): LibraryRepository =
            instance ?: synchronized(this) {
                instance ?: LibraryRepository(
                    context = context.applicationContext,
                    authRepository = AuthRepository.getInstance(context.applicationContext),
                ).also { instance = it }
            }
    }
}
