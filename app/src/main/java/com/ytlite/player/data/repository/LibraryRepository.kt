package com.ytlite.player.data.repository

import android.content.Context
import com.ytlite.player.data.auth.AuthRepository
import com.ytlite.player.data.auth.SupabaseClientProvider
import com.ytlite.player.data.auth.UserProfile
import com.ytlite.player.data.auth.UserSession
import com.ytlite.player.data.local.YTLiteDatabase
import com.ytlite.player.data.local.entity.PlaylistEntity
import com.ytlite.player.data.local.entity.PlaylistSystemType
import com.ytlite.player.data.local.entity.PlaylistTrackEntity
import com.ytlite.player.data.local.model.LibraryVideoRow
import com.ytlite.player.data.model.DataSource
import com.ytlite.player.data.model.LibraryFilterChip
import com.ytlite.player.data.model.LibraryItem
import com.ytlite.player.data.model.LibrarySort
import com.ytlite.player.data.model.LibraryVideo
import com.ytlite.player.data.remote.SupabaseLibraryRemote
import com.ytlite.player.data.remote.dto.PlaylistDto
import com.ytlite.player.data.remote.dto.PlaylistTrackDto
import com.ytlite.player.data.remote.youtube.YoutubeRemoteDataSource
import com.ytlite.player.data.youtube.YoutubeDiagnostics
import com.ytlite.player.playback.NowPlaying
import com.ytlite.player.playback.PlaybackManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

class LibraryRepository(
    context: Context,
    private val authRepository: AuthRepository,
    private val youtubeRemote: YoutubeRemoteDataSource,
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

    private val playbackHistoryRepository = PlaybackHistoryRepository(database, remote)
    private val repositoryScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val systemPlaylistsEnsured = ConcurrentHashMap.newKeySet<String>()

    init {
        authRepository.onMergeGuestData = { guestOwnerKey, userId, profile ->
            mergeGuestDataIntoUser(guestOwnerKey, userId, profile)
        }
        authRepository.onSwitchToGuestMode = { userOwnerKey, guestOwnerKey ->
            migrateUserLocalDataToGuest(userOwnerKey, guestOwnerKey)
        }
        authRepository.onAuthenticated = { profile ->
            youtubeRemote.setOwnerKey("user:${profile.userId}")
            YoutubeDiagnostics.d(
                step = "Playlists/Repo",
                message = "onAuthenticated userId=${profile.userId} scheduling refreshYoutubePlaylists",
            )
            repositoryScope.launch {
                refreshYoutubePlaylists()
            }
        }
        authRepository.onSignedOut = {
            youtubeRemote.setOwnerKey(null)
        }
        PlaybackManager.onProgressTick = { videoId, progressMs ->
            repositoryScope.launch {
                val ownerKey = authRepository.currentSession()?.ownerKey ?: return@launch
                playbackHistoryRepository.updateProgress(ownerKey, videoId, progressMs)
            }
        }
    }

    fun observeHistory(ownerKey: String, limit: Int = 20): Flow<List<LibraryVideo>> =
        userTrackLastPlayedDao.observeHistoryRows(ownerKey, limit).map { rows ->
            rows.map { it.toLibraryVideo() }
        }

    fun currentOwnerKey(): String? = authRepository.currentSession()?.ownerKey

    fun getUnifiedPlaylists(ownerKey: String): Flow<List<PlaylistEntity>> =
        combine(
            playlistDao.observeLocalByOwner(ownerKey).map { dedupeLocalPlaylistsForDisplay(it) },
            youtubeRemote.getYoutubePlaylistsFlow(),
        ) { local, youtube ->
            (local + youtube).sortedByDescending { it.updatedAt }
        }.flowOn(Dispatchers.Default)

    fun observeLikedCount(ownerKey: String): Flow<Int> =
        playlistTrackDao.observeSystemPlaylistCount(ownerKey, PlaylistSystemType.FAVORITES)

    fun observeWatchLaterCount(ownerKey: String): Flow<Int> =
        playlistTrackDao.observeSystemPlaylistCount(ownerKey, PlaylistSystemType.WATCH_LATER)

    fun observeLibraryItems(
        ownerKey: String,
        filter: LibraryFilterChip?,
        sort: LibrarySort,
        isAuthenticated: Boolean,
    ): Flow<List<LibraryItem>> = when (filter) {
        null -> combine(
            playlistDao.observeLocalByOwner(ownerKey).map { dedupeLocalPlaylistsForDisplay(it) },
            playlistTrackDao.observeLocalSongs(ownerKey),
            artistDao.observeAll(),
            observeHistory(ownerKey, limit = 50),
        ) { playlists, songs, artists, history ->
            val playlistItems = playlists.map {
                LibraryItemMapper.playlistItem(it, LibraryItemMapper.playlistSubtitle(it))
            }
            val songItems = buildSongItems(songs, history)
            val artistItems = artists.map { LibraryItemMapper.artistItem(it) }
            LibraryItemMapper.mergeLocalMixed(playlistItems, songItems, artistItems, sort)
        }
        LibraryFilterChip.PLAYLISTS -> playlistDao.observeLocalByOwner(ownerKey)
            .map { playlists ->
                LibraryItemMapper.sortItems(
                    dedupeLocalPlaylistsForDisplay(playlists).map {
                        LibraryItemMapper.playlistItem(it, LibraryItemMapper.playlistSubtitle(it))
                    },
                    sort,
                )
            }
        LibraryFilterChip.SONGS -> combine(
            playlistTrackDao.observeLocalSongs(ownerKey),
            observeHistory(ownerKey, limit = 100),
        ) { songs, history ->
            LibraryItemMapper.sortItems(buildSongItems(songs, history), sort)
        }
        LibraryFilterChip.ARTISTS -> artistDao.observeAll().map { artists ->
            LibraryItemMapper.sortItems(artists.map { LibraryItemMapper.artistItem(it) }, sort)
        }
        LibraryFilterChip.DOWNLOADS -> flowOf(emptyList())
        LibraryFilterChip.YOUTUBE -> if (!isAuthenticated) {
            flowOf(emptyList())
        } else {
            youtubeRemote.getYoutubePlaylistsFlow().map { playlists ->
                LibraryItemMapper.sortItems(
                    playlists.map {
                        LibraryItemMapper.playlistItem(it, LibraryItemMapper.playlistSubtitle(it))
                    },
                    sort,
                )
            }
        }
    }.flowOn(Dispatchers.Default)

    fun observeAllHistory(ownerKey: String): Flow<List<LibraryVideo>> =
        userTrackLastPlayedDao.observeAllHistoryRows(ownerKey).map { rows ->
            rows.map { it.toLibraryVideo() }
        }

    fun observePlaylistTrackDetails(playlistId: String) =
        playlistTrackDao.observePlaylistTrackDetails(playlistId)

    suspend fun getPlaylistById(
        playlistId: String,
        ownerKey: String,
        systemType: String? = null,
    ): PlaylistEntity? = withContext(Dispatchers.IO) {
        if (systemType != null) {
            playlistDao.getSystemPlaylist(ownerKey, systemType)?.let { return@withContext it }
        }
        playlistDao.getAllByOwner(ownerKey).firstOrNull { it.playlistId == playlistId }
            ?: youtubeRemote.getYoutubePlaylistsFlow().first()
                .firstOrNull { it.playlistId == playlistId }
    }

    fun observeIsTrackLiked(ownerKey: String, trackId: String): Flow<Boolean> =
        playlistTrackDao.observeTrackInSystemPlaylist(
            ownerKey,
            PlaylistSystemType.FAVORITES,
            trackId,
        )

    suspend fun addTrackToFavorites(ownerKey: String, video: LibraryVideo) =
        addTrackToSystemPlaylist(ownerKey, PlaylistSystemType.FAVORITES, video)

    suspend fun removeTrackFromFavorites(ownerKey: String, trackId: String) =
        removeTrackFromSystemPlaylist(ownerKey, PlaylistSystemType.FAVORITES, trackId)

    suspend fun removeTrackFromPlaylist(playlistId: String, trackId: String) =
        withContext(Dispatchers.IO) {
            playlistTrackDao.deleteTrack(playlistId, trackId)
        }

    suspend fun createLocalPlaylist(ownerKey: String, name: String): String =
        withContext(Dispatchers.IO) {
            ensureSystemPlaylists(ownerKey)
            val playlistId = UUID.randomUUID().toString()
            playlistDao.upsert(
                PlaylistEntity(
                    playlistId = playlistId,
                    ownerKey = ownerKey,
                    name = name,
                    source = DataSource.LOCAL.dbValue,
                    updatedAt = System.currentTimeMillis(),
                ),
            )
            playlistId
        }

    suspend fun addTrackToPlaylist(playlistId: String, video: LibraryVideo) =
        withContext(Dispatchers.IO) {
            playbackHistoryRepository.depositPlayback(
                video = video,
                ownerKey = authRepository.currentSession()?.ownerKey ?: return@withContext,
                userId = (authRepository.currentSession() as? UserSession.Authenticated)?.profile?.userId,
            )
            val existing = playlistTrackDao.getAllByPlaylist(playlistId)
            if (existing.any { it.trackId == video.videoId }) return@withContext
            playlistTrackDao.upsert(
                PlaylistTrackEntity(
                    playlistId = playlistId,
                    trackId = video.videoId,
                    position = existing.size,
                ),
            )
        }

    private suspend fun addTrackToSystemPlaylist(
        ownerKey: String,
        systemType: String,
        video: LibraryVideo,
    ) = withContext(Dispatchers.IO) {
        ensureSystemPlaylists(ownerKey)
        val playlist = playlistDao.getSystemPlaylist(ownerKey, systemType) ?: return@withContext
        playbackHistoryRepository.depositPlayback(
            video = video,
            ownerKey = ownerKey,
            userId = (authRepository.currentSession() as? UserSession.Authenticated)?.profile?.userId,
        )
        val existing = playlistTrackDao.getAllByPlaylist(playlist.playlistId)
        if (existing.any { it.trackId == video.videoId }) return@withContext
        playlistTrackDao.upsert(
            PlaylistTrackEntity(
                playlistId = playlist.playlistId,
                trackId = video.videoId,
                position = existing.size,
            ),
        )
    }

    private suspend fun removeTrackFromSystemPlaylist(
        ownerKey: String,
        systemType: String,
        trackId: String,
    ) = withContext(Dispatchers.IO) {
        val playlist = playlistDao.getSystemPlaylist(ownerKey, systemType) ?: return@withContext
        playlistTrackDao.deleteTrack(playlist.playlistId, trackId)
    }

    private fun buildSongItems(
        songs: List<com.ytlite.player.data.local.model.LibrarySongRow>,
        history: List<LibraryVideo>,
    ): List<LibraryItem.Song> {
        val merged = LinkedHashMap<String, LibraryItem.Song>()
        songs.forEach { merged[it.trackId] = LibraryItemMapper.songItem(it) }
        history.forEach { video ->
            merged.putIfAbsent(video.videoId, LibraryItemMapper.songFromVideo(video))
        }
        return merged.values.toList()
    }

    suspend fun refreshYoutubePlaylists() {
        val session = authRepository.currentSession()
        val token = authRepository.getGoogleProviderAccessToken()
        val needsReauth = authRepository.needsYoutubeDataApiReauth()
        YoutubeDiagnostics.logPlaylistsFetchStart(
            step = "Playlists/Repo",
            ownerKey = session?.ownerKey,
            sessionType = session?.javaClass?.simpleName ?: "null",
            apiConfigured = authRepository.isYoutubeDataApiKeyConfigured(),
            needsReauth = needsReauth,
            tokenPresent = !token.isNullOrBlank(),
            tokenLength = token?.length ?: 0,
            tokenSource = authRepository.diagnoseGoogleAccessTokenSource(),
        )
        if (needsReauth) {
            YoutubeDiagnostics.logPlaylistsFetchOutcome(
                step = "Playlists/Repo",
                outcome = "skipped",
                detail = "needsYoutubeDataApiReauth=true → clearing youtube playlists",
            )
            youtubeRemote.refreshPlaylists(null)
            return
        }
        youtubeRemote.refreshPlaylists(token)
    }

    suspend fun ensureLocalLibraryReady(ownerKey: String) {
        ensureSystemPlaylists(ownerKey)
        deduplicateSystemPlaylists(ownerKey)
    }

    suspend fun importYoutubePlaylistToLocal(
        youtubePlaylistId: String,
        ownerKey: String,
    ) = withContext(Dispatchers.IO) {
        val sourcePlaylist = youtubeRemote.getYoutubePlaylistsFlow()
            .first()
            .firstOrNull { it.playlistId == youtubePlaylistId } ?: return@withContext
        val tracks = youtubeRemote.getPlaylistTracks(
            youtubePlaylistId,
            authRepository.getGoogleProviderAccessToken(),
        )
        val newPlaylistId = UUID.randomUUID().toString()
        val now = System.currentTimeMillis()
        playlistDao.upsert(
            sourcePlaylist.copy(
                playlistId = newPlaylistId,
                ownerKey = ownerKey,
                source = DataSource.LOCAL.dbValue,
                isSynced = false,
                updatedAt = now,
            ),
        )
        tracks.forEachIndexed { index, trackRef ->
            playlistTrackDao.upsert(
                trackRef.copy(
                    playlistId = newPlaylistId,
                    position = index,
                    isSynced = false,
                ),
            )
        }
    }

    suspend fun addToHistory(
        video: LibraryVideo,
        ownerKey: String,
        progressMs: Long = 0L,
    ) = withContext(Dispatchers.IO) {
        ensureSystemPlaylists(ownerKey)
        val userId = (authRepository.currentSession() as? UserSession.Authenticated)?.profile?.userId
        playbackHistoryRepository.depositPlayback(
            video = video,
            ownerKey = ownerKey,
            progressMs = progressMs,
            userId = userId,
        )
    }

    suspend fun addToHistory(nowPlaying: NowPlaying) {
        if (authRepository.currentSession() == null) {
            authRepository.initialize()
        }
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

    suspend fun migrateUserLocalDataToGuest(
        userOwnerKey: String,
        guestOwnerKey: String,
    ) = withContext(Dispatchers.IO) {
        ensureSystemPlaylists(guestOwnerKey)

        val guestFavorites = playlistDao.getSystemPlaylist(guestOwnerKey, PlaylistSystemType.FAVORITES)
        val guestWatchLater = playlistDao.getSystemPlaylist(guestOwnerKey, PlaylistSystemType.WATCH_LATER)
        val userFavorites = playlistDao.getSystemPlaylist(userOwnerKey, PlaylistSystemType.FAVORITES)
        val userWatchLater = playlistDao.getSystemPlaylist(userOwnerKey, PlaylistSystemType.WATCH_LATER)

        if (guestFavorites != null && userFavorites != null) {
            mergePlaylistTracks(userFavorites.playlistId, guestFavorites.playlistId)
        }
        if (guestWatchLater != null && userWatchLater != null) {
            mergePlaylistTracks(userWatchLater.playlistId, guestWatchLater.playlistId)
        }

        mergeUserHistoryToGuest(userOwnerKey, guestOwnerKey)
        playbackHistoryDao.migrateOwnerKey(userOwnerKey, guestOwnerKey)

        playlistDao.getAllByOwner(userOwnerKey)
            .filter { it.isLocal() && it.systemType == null }
            .forEach { playlist ->
                playlistDao.upsert(
                    playlist.copy(
                        ownerKey = guestOwnerKey,
                        userId = null,
                        isSynced = false,
                        updatedAt = System.currentTimeMillis(),
                    ),
                )
            }

        deduplicateSystemPlaylists(guestOwnerKey)
    }

    suspend fun mergeGuestDataIntoUser(
        guestOwnerKey: String,
        userId: String,
        profile: UserProfile,
    ) = withContext(Dispatchers.IO) {
        val userOwnerKey = "user:$userId"

        ensureSystemPlaylists(guestOwnerKey)

        playlistDao.getAllByOwner(guestOwnerKey)
            .filter { it.systemType != null }
            .forEach { playlist ->
                playlistDao.upsert(
                    playlist.copy(
                        ownerKey = userOwnerKey,
                        userId = userId,
                        isSynced = false,
                        updatedAt = System.currentTimeMillis(),
                    ),
                )
            }

        systemPlaylistsEnsured.remove(userOwnerKey)
        ensureSystemPlaylists(userOwnerKey, userId)
        deduplicateSystemPlaylists(userOwnerKey)

        userTrackLastPlayedDao.migrateOwnerKey(guestOwnerKey, userOwnerKey)
        playbackHistoryDao.migrateOwnerKey(guestOwnerKey, userOwnerKey)

        val guestPlaylists = playlistDao.getAllByOwner(guestOwnerKey)
            .filter { it.systemType == null }
        guestPlaylists.forEach { guestPlaylist ->
            val migrated = guestPlaylist.copy(
                ownerKey = userOwnerKey,
                userId = userId,
                isSynced = false,
                updatedAt = System.currentTimeMillis(),
            )
            playlistDao.upsert(migrated)
            playlistTrackDao.migratePlaylistId(guestPlaylist.playlistId, migrated.playlistId)
        }

        uploadLocalDataToRemote(userId, userOwnerKey)
        remote?.upsertProfile(profile)
        pullRemoteIntoLocal(userId, userOwnerKey)
        deduplicateSystemPlaylists(userOwnerKey)
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
        deduplicateSystemPlaylists(userOwnerKey)

        remoteClient.fetchProfile(userId)?.let { authRepository.updateAuthenticatedProfile(it) }
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

        val now = System.currentTimeMillis()
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
                source = DataSource.LOCAL.dbValue,
                isSynced = userId != null,
                updatedAt = now,
            ),
        )
    }

    private suspend fun mergeUserHistoryToGuest(
        userOwnerKey: String,
        guestOwnerKey: String,
    ) {
        val guestByTrack = userTrackLastPlayedDao.getAllByOwner(guestOwnerKey)
            .associateBy { it.trackId }
        userTrackLastPlayedDao.getAllByOwner(userOwnerKey).forEach { userEntry ->
            val guestEntry = guestByTrack[userEntry.trackId]
            val merged = when {
                guestEntry == null || userEntry.lastPlayedAt >= guestEntry.lastPlayedAt ->
                    userEntry.copy(ownerKey = guestOwnerKey, isSynced = false)
                else -> guestEntry
            }
            userTrackLastPlayedDao.upsert(merged)
        }
        userTrackLastPlayedDao.deleteByOwner(userOwnerKey)
    }

    private suspend fun deduplicateSystemPlaylists(ownerKey: String) {
        listOf(PlaylistSystemType.FAVORITES, PlaylistSystemType.WATCH_LATER).forEach { systemType ->
            val duplicates = playlistDao.getAllByOwner(ownerKey)
                .filter { it.isLocal() && it.systemType == systemType }
            if (duplicates.size <= 1) return@forEach

            val duplicatesWithTrackCounts = duplicates.map { playlist ->
                playlist to playlistTrackDao.getAllByPlaylist(playlist.playlistId).size
            }
            val canonical = duplicatesWithTrackCounts.maxWithOrNull(
                compareBy<Pair<PlaylistEntity, Int>> { it.first.isSynced }
                    .thenBy { it.second }
                    .thenBy { it.first.updatedAt },
            )?.first ?: return@forEach

            duplicates
                .filter { it.playlistId != canonical.playlistId }
                .forEach { duplicate ->
                    mergePlaylistTracks(duplicate.playlistId, canonical.playlistId)
                    playlistTrackDao.deleteAllByPlaylist(duplicate.playlistId)
                    playlistDao.deleteById(duplicate.playlistId)
                }
        }
    }

    private fun dedupeLocalPlaylistsForDisplay(playlists: List<PlaylistEntity>): List<PlaylistEntity> {
        val customPlaylists = playlists.filter { it.systemType == null }
        val systemPlaylists = playlists
            .filter { it.systemType != null }
            .groupBy { it.systemType }
            .mapNotNull { (_, group) ->
                group.maxWithOrNull(
                    compareBy<PlaylistEntity> { it.isSynced }
                        .thenBy { it.updatedAt },
                )
            }
        return (systemPlaylists + customPlaylists).sortedByDescending { it.updatedAt }
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
                source = DataSource.LOCAL.dbValue,
                isSynced = true,
                updatedAt = System.currentTimeMillis(),
            ),
        )

        if (localPlaylist != null && localPlaylist.playlistId != playlistId) {
            mergePlaylistTracks(localPlaylist.playlistId, playlistId)
            playlistTrackDao.deleteAllByPlaylist(localPlaylist.playlistId)
            playlistDao.deleteById(localPlaylist.playlistId)
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
                    youtubeRemote = YoutubeRemoteDataSource.getInstance(),
                ).also { instance = it }
            }
    }
}
