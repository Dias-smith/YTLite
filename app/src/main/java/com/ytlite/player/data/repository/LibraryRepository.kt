package com.ytlite.player.data.repository

import android.content.Context
import com.ytlite.player.data.auth.AuthRepository
import com.ytlite.player.data.auth.SupabaseClientProvider
import com.ytlite.player.data.auth.UserProfile
import com.ytlite.player.data.auth.UserSession
import com.ytlite.player.data.local.YTLiteDatabase
import com.ytlite.player.data.local.entity.PlaylistEntity
import com.ytlite.player.data.local.entity.PlaylistDisplayOrderEntity
import com.ytlite.player.data.local.entity.PlaylistPinOverlayEntity
import com.ytlite.player.data.local.entity.PlaylistSystemType
import com.ytlite.player.data.local.entity.PlaylistTrackEntity
import com.ytlite.player.data.local.entity.UserTrackMetadataEntity
import com.ytlite.player.data.local.model.LibraryVideoRow
import com.ytlite.player.data.model.DataSource
import com.ytlite.player.data.model.LibraryFilterChip
import com.ytlite.player.data.model.LibraryItem
import com.ytlite.player.data.model.LibrarySort
import com.ytlite.player.data.model.LibraryVideo
import com.ytlite.player.data.model.ResolvedTrackMetadata
import com.ytlite.player.data.model.TrackMetadataEdits
import com.ytlite.player.data.model.TrackMetadataSeed
import com.ytlite.player.data.remote.SupabaseLibraryRemote
import com.ytlite.player.data.remote.dto.PlaylistDto
import com.ytlite.player.data.remote.dto.PlaylistTrackDto
import com.ytlite.player.data.remote.toEntity
import com.ytlite.player.data.remote.toPlaylistDto
import com.ytlite.player.data.remote.toPlaylistEntity
import com.ytlite.player.data.remote.updatedAtMillis
import com.ytlite.player.data.remote.youtube.YoutubeRemoteDataSource
import com.ytlite.player.data.youtube.YoutubeDiagnostics
import com.ytlite.player.playback.NowPlaying
import com.ytlite.player.playback.PlaybackCacheJanitor
import com.ytlite.player.playback.PlaybackManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
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
    private val playlistPinOverlayDao = database.playlistPinOverlayDao()
    private val playlistDisplayOrderDao = database.playlistDisplayOrderDao()
    private val playlistTrackDao = database.playlistTrackDao()
    private val playbackHistoryDao = database.playbackHistoryDao()
    private val userTrackLastPlayedDao = database.userTrackLastPlayedDao()
    private val notInterestedDao = database.notInterestedDao()
    private val userTrackMetadataDao = database.userTrackMetadataDao()

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
        PlaybackManager.onCacheablePlay = { videoId, cacheKey, itag ->
            repositoryScope.launch {
                PlaybackCacheJanitor.recordPlay(
                    context = appContext,
                    videoId = videoId,
                    cacheKey = cacheKey,
                    itag = itag,
                    ownerKey = authRepository.currentSession()?.ownerKey,
                )
            }
        }
        repositoryScope.launch {
            PlaybackCacheJanitor.purgeExpired(
                context = appContext,
                ownerKey = authRepository.currentSession()?.ownerKey,
            )
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
            playlistPinOverlayDao.observeByOwner(ownerKey),
        ) { local, youtube, overlays ->
            orderPlaylistEntitiesByPin(applyPinOverlay(youtube, overlays) + local)
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
        LibraryFilterChip.PLAYLISTS -> combine(
            playlistDao.observeLocalByOwner(ownerKey).map { dedupeLocalPlaylistsForDisplay(it) },
            playlistDisplayOrderDao.observeByOwner(ownerKey),
        ) { playlists, displayOrders ->
            val manualOrder = if (sort == LibrarySort.CUSTOM) {
                displayOrders.associate { it.playlistKey to it.position }
            } else {
                emptyMap()
            }
            LibraryItemMapper.orderPlaylistItems(
                playlists.map {
                    LibraryItemMapper.playlistItem(it, LibraryItemMapper.playlistSubtitle(it))
                },
                sort,
                manualOrder = manualOrder,
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
        LibraryFilterChip.ALBUMS -> userTrackMetadataDao.observeDistinctAlbums(ownerKey).map { albums ->
            LibraryItemMapper.sortItems(
                albums.map { LibraryItemMapper.albumItem(it) },
                sort,
            )
        }
        LibraryFilterChip.YOUTUBE -> if (!isAuthenticated) {
            flowOf(emptyList())
        } else {
            combine(
                youtubeRemote.getYoutubePlaylistsFlow(),
                playlistPinOverlayDao.observeByOwner(ownerKey),
            ) { playlists, overlays ->
                LibraryItemMapper.orderPlaylistItems(
                    applyPinOverlay(playlists, overlays).map {
                        LibraryItemMapper.playlistItem(it, LibraryItemMapper.playlistSubtitle(it))
                    },
                    sort,
                    includeHistory = false,
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

    fun observePlaylistStats(playlistId: String) =
        playlistTrackDao.observePlaylistStats(playlistId)

    suspend fun getPlaylistQueueItems(
        ownerKey: String,
        playlistId: String,
        systemType: String?,
    ): List<com.ytlite.player.playback.QueueItem> = withContext(Dispatchers.IO) {
        when (systemType) {
            PlaylistSystemType.HISTORY -> {
                observeAllHistory(ownerKey).first().map { video ->
                    com.ytlite.player.playback.QueueItem(
                        videoId = video.videoId,
                        title = video.title,
                        channelName = video.channelName,
                        thumbnailUrl = video.thumbnailUrl,
                        album = video.album,
                        year = video.year,
                    )
                }
            }
            else -> {
                val resolvedId = resolvePlaylistIdForAction(ownerKey, playlistId, systemType)
                    ?: return@withContext emptyList()
                observePlaylistTrackDetails(resolvedId).first().map { track ->
                    com.ytlite.player.playback.QueueItem(
                        videoId = track.trackId,
                        title = track.title,
                        channelName = track.primaryArtistName.orEmpty(),
                        thumbnailUrl = track.thumbnailUrl,
                        durationText = track.durationText,
                        album = track.album,
                        year = track.year,
                    )
                }
            }
        }
    }

    suspend fun renameLocalPlaylist(playlistId: String, ownerKey: String, name: String): Boolean =
        withContext(Dispatchers.IO) {
            val playlist = findOwnedLocalCustomPlaylist(playlistId, ownerKey) ?: return@withContext false
            playlistDao.upsert(
                playlist.copy(
                    name = name.trim(),
                    updatedAt = System.currentTimeMillis(),
                    isSynced = false,
                ),
            )
            schedulePlaylistUpload()
            true
        }

    suspend fun reorderPlaylistTracks(
        playlistId: String,
        ownerKey: String,
        orderedTrackIds: List<String>,
    ): Boolean = withContext(Dispatchers.IO) {
        val playlist = findOwnedLocalPlaylist(playlistId, ownerKey) ?: return@withContext false
        if (playlist.isYoutube()) return@withContext false
        val existing = playlistTrackDao.getAllByPlaylist(playlistId).associateBy { it.trackId }
        val rewritten = orderedTrackIds.mapIndexedNotNull { index, trackId ->
            existing[trackId]?.copy(position = index, isSynced = false)
        }
        if (rewritten.size != orderedTrackIds.size) return@withContext false
        playlistTrackDao.upsertAll(rewritten)
        playlistDao.upsert(
            playlist.copy(
                updatedAt = System.currentTimeMillis(),
                isSynced = false,
            ),
        )
        schedulePlaylistUpload()
        true
    }

    suspend fun togglePlaylistPin(playlistId: String, ownerKey: String): Boolean =
        withContext(Dispatchers.IO) {
            val localPlaylist = findOwnedLocalPlaylist(playlistId, ownerKey)
            var playlistKey: String? = null
            var nowPinned = false
            val success = when {
                localPlaylist != null -> {
                    val now = System.currentTimeMillis()
                    val updated = if (!localPlaylist.isPinned) {
                        localPlaylist.copy(
                            isPinned = true,
                            unpinnedSortAt = localPlaylist.updatedAt,
                            pinnedAt = now,
                            isSynced = false,
                        )
                    } else {
                        localPlaylist.copy(
                            isPinned = false,
                            updatedAt = localPlaylist.unpinnedSortAt ?: localPlaylist.updatedAt,
                            unpinnedSortAt = null,
                            pinnedAt = null,
                            isSynced = false,
                        )
                    }
                    playlistKey = LibraryItemMapper.playlistListKey(updated)
                    nowPinned = updated.isPinned
                    playlistDao.upsert(updated)
                    true
                }
                else -> {
                    val youtubePlaylist = findYoutubePlaylist(playlistId) ?: return@withContext false
                    val overlay = playlistPinOverlayDao.observeByPlaylist(ownerKey, playlistId).first()
                    val currentlyPinned = overlay?.isPinned ?: false
                    val now = System.currentTimeMillis()
                    nowPinned = !currentlyPinned
                    playlistKey = playlistId
                    playlistPinOverlayDao.upsert(
                        if (!currentlyPinned) {
                            PlaylistPinOverlayEntity(
                                playlistId = playlistId,
                                ownerKey = ownerKey,
                                isPinned = true,
                                unpinnedSortAt = youtubePlaylist.updatedAt,
                                pinnedAt = now,
                                updatedAt = now,
                            )
                        } else {
                            PlaylistPinOverlayEntity(
                                playlistId = playlistId,
                                ownerKey = ownerKey,
                                isPinned = false,
                                unpinnedSortAt = overlay?.unpinnedSortAt,
                                pinnedAt = null,
                                updatedAt = now,
                            )
                        },
                    )
                    true
                }
            }
            if (success) {
                if (localPlaylist != null) {
                    schedulePlaylistUpload()
                }
                playlistKey?.let { key ->
                    moveDisplayOrderOnPinToggle(ownerKey, key, nowPinned)
                }
            }
            success
        }

    fun observePlaylistDisplayOrder(ownerKey: String): Flow<List<PlaylistDisplayOrderEntity>> =
        playlistDisplayOrderDao.observeByOwner(ownerKey)

    suspend fun seedDisplayOrderFromCurrent(
        ownerKey: String,
        items: List<LibraryItem.Playlist>,
    ) = withContext(Dispatchers.IO) {
        val entities = buildList {
            items.filter { it.isPinned }.forEachIndexed { index, item ->
                add(
                    PlaylistDisplayOrderEntity(
                        ownerKey = ownerKey,
                        playlistKey = item.id,
                        pinGroup = true,
                        position = index,
                    ),
                )
            }
            items.filter { !it.isPinned }.forEachIndexed { index, item ->
                add(
                    PlaylistDisplayOrderEntity(
                        ownerKey = ownerKey,
                        playlistKey = item.id,
                        pinGroup = false,
                        position = index,
                    ),
                )
            }
        }
        playlistDisplayOrderDao.upsertAll(entities)
    }

    suspend fun reorderPlaylistInGroup(
        ownerKey: String,
        pinGroup: Boolean,
        fromPosition: Int,
        toPosition: Int,
    ) = withContext(Dispatchers.IO) {
        val group = playlistDisplayOrderDao.getAllByOwner(ownerKey)
            .filter { it.pinGroup == pinGroup }
            .sortedBy { it.position }
            .toMutableList()
        if (fromPosition !in group.indices || toPosition !in group.indices) return@withContext
        val moved = group.removeAt(fromPosition)
        group.add(toPosition, moved)
        playlistDisplayOrderDao.upsertAll(
            group.mapIndexed { index, entity -> entity.copy(position = index) },
        )
    }

    suspend fun moveDisplayOrderOnPinToggle(
        ownerKey: String,
        playlistKey: String,
        nowPinned: Boolean,
    ) = withContext(Dispatchers.IO) {
        val all = playlistDisplayOrderDao.getAllByOwner(ownerKey)
        if (all.isEmpty()) return@withContext
        playlistDisplayOrderDao.deleteByKey(ownerKey, playlistKey)
        val targetGroup = all.filter { it.pinGroup == nowPinned && it.playlistKey != playlistKey }
        val newPosition = (targetGroup.maxOfOrNull { it.position } ?: -1) + 1
        playlistDisplayOrderDao.upsertAll(
            listOf(
                PlaylistDisplayOrderEntity(
                    ownerKey = ownerKey,
                    playlistKey = playlistKey,
                    pinGroup = nowPinned,
                    position = newPosition,
                ),
            ),
        )
    }

    fun observePlaylistPin(playlistId: String, ownerKey: String): Flow<Boolean> =
        combine(
            playlistDao.observeById(playlistId).map { it?.isPinned == true },
            playlistPinOverlayDao.observeByPlaylist(ownerKey, playlistId).map { it?.isPinned == true },
        ) { localPinned, overlayPinned -> localPinned || overlayPinned }
            .distinctUntilChanged()

    fun observeLocalPlaylist(playlistId: String): Flow<PlaylistEntity?> =
        playlistDao.observeById(playlistId)

    suspend fun deleteLocalPlaylist(playlistId: String, ownerKey: String): Boolean =
        withContext(Dispatchers.IO) {
            val playlist = findOwnedLocalCustomPlaylist(playlistId, ownerKey) ?: return@withContext false
            playlistTrackDao.deleteAllByPlaylist(playlistId)
            playlistDao.deleteById(playlistId)
            authRepository.currentSession()?.let { session ->
                if (session is UserSession.Authenticated) {
                    remote?.deletePlaylist(playlistId)
                }
            }
            true
        }

    suspend fun removeTracksFromLocalLibrary(ownerKey: String, trackIds: List<String>) =
        withContext(Dispatchers.IO) {
            trackIds.distinct().forEach { trackId ->
                playlistTrackDao.deleteTrackFromAllLocalPlaylists(ownerKey, trackId)
            }
        }

    suspend fun deleteLocalPlaylists(ownerKey: String, playlistIds: List<String>): Int =
        withContext(Dispatchers.IO) {
            var deleted = 0
            playlistIds.distinct().forEach { playlistId ->
                if (deleteLocalPlaylist(playlistId, ownerKey)) {
                    deleted++
                }
            }
            deleted
        }

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

    fun observeIsNotInterested(ownerKey: String, videoId: String): Flow<Boolean> =
        notInterestedDao.observeIsNotInterested(ownerKey, videoId)

    suspend fun addNotInterested(ownerKey: String, videoId: String) =
        withContext(Dispatchers.IO) {
            notInterestedDao.upsert(
                com.ytlite.player.data.local.entity.NotInterestedEntity(
                    ownerKey = ownerKey,
                    videoId = videoId,
                    createdAt = System.currentTimeMillis(),
                ),
            )
        }

    suspend fun removeNotInterested(ownerKey: String, videoId: String) =
        withContext(Dispatchers.IO) {
            notInterestedDao.delete(ownerKey, videoId)
        }

    fun observeTrackMetadata(ownerKey: String, trackId: String) =
        userTrackMetadataDao.observe(ownerKey, trackId)

    fun observeAlbumTracks(ownerKey: String, album: String) =
        userTrackMetadataDao.observeTracksByAlbum(ownerKey, album)
            .map { rows -> rows.map { row -> row.toLibraryVideo() } }

    suspend fun getResolvedMetadata(ownerKey: String, trackId: String): ResolvedTrackMetadata? =
        withContext(Dispatchers.IO) {
            val canonical = trackDao.getById(trackId) ?: return@withContext null
            val override = userTrackMetadataDao.getById(ownerKey, trackId)
            TrackMetadataResolver.resolve(canonical, override)
        }

    suspend fun getResolvedMetadataForEdit(
        ownerKey: String,
        trackId: String,
        seed: TrackMetadataSeed?,
    ): ResolvedTrackMetadata? = withContext(Dispatchers.IO) {
        val canonical = trackDao.getById(trackId)
        val override = userTrackMetadataDao.getById(ownerKey, trackId)
        if (canonical != null) {
            return@withContext TrackMetadataResolver.resolve(canonical, override)
        }
        seed ?: return@withContext null
        TrackMetadataResolver.resolveForQueueItem(seed.toQueueItem(), override)
    }

    suspend fun ensureCanonicalTrack(
        trackId: String,
        title: String,
        artistName: String,
        thumbnailUrl: String,
        channelId: String? = null,
    ) = withContext(Dispatchers.IO) {
        if (trackDao.getById(trackId) != null) return@withContext
        trackDao.upsert(
            com.ytlite.player.data.local.entity.TrackEntity(
                trackId = trackId,
                title = title,
                thumbnailHigh = thumbnailUrl.takeIf { it.isNotBlank() },
                primaryArtistName = artistName.takeIf { it.isNotBlank() },
                primaryArtistId = channelId?.takeIf { it.isNotBlank() },
            ),
        )
    }

    suspend fun upsertTrackMetadata(
        ownerKey: String,
        trackId: String,
        edits: TrackMetadataEdits,
    ): ResolvedTrackMetadata? = withContext(Dispatchers.IO) {
        val canonical = trackDao.getById(trackId)
        if (edits.isEmpty()) {
            resetTrackMetadata(ownerKey, trackId)
            return@withContext canonical?.let { TrackMetadataResolver.resolve(it, override = null) }
        }
        val now = System.currentTimeMillis()
        val entity = UserTrackMetadataEntity(
            ownerKey = ownerKey,
            trackId = trackId,
            customTitle = edits.title,
            customArtistName = edits.artistName,
            customThumbnailUrl = edits.thumbnailUrl,
            customAlbum = edits.album,
            customYear = edits.year,
            updatedAt = now,
            isSynced = false,
        )
        userTrackMetadataDao.upsert(entity)
        val resolved = if (canonical != null) {
            TrackMetadataResolver.resolve(canonical, entity)
        } else {
            ResolvedTrackMetadata(
                trackId = trackId,
                title = edits.title.orEmpty(),
                artistName = edits.artistName.orEmpty(),
                thumbnailUrl = edits.thumbnailUrl.orEmpty(),
                album = edits.album,
                year = edits.year,
                hasUserOverride = true,
            )
        }
        authRepository.currentSession()?.let { session ->
            if (session is UserSession.Authenticated) {
                syncTrackMetadataToRemote(session.profile.userId, ownerKey, entity)
            }
        }
        resolved
    }

    suspend fun resetTrackMetadata(ownerKey: String, trackId: String) = withContext(Dispatchers.IO) {
        userTrackMetadataDao.delete(ownerKey, trackId)
        authRepository.currentSession()?.let { session ->
            if (session is UserSession.Authenticated) {
                remote?.deleteUserTrackMetadata(session.profile.userId, trackId)
            }
        }
    }

    private suspend fun syncTrackMetadataToRemote(
        userId: String,
        ownerKey: String,
        entity: UserTrackMetadataEntity,
    ) {
        val remoteClient = remote ?: return
        remoteClient.upsertUserTrackMetadata(userId, entity)
        userTrackMetadataDao.markSynced(ownerKey, entity.trackId)
    }

    suspend fun removeTrackFromPlaylist(playlistId: String, trackId: String) =
        withContext(Dispatchers.IO) {
            playlistTrackDao.deleteTrack(playlistId, trackId)
            playlistDao.markUnsynced(playlistId)
            evaluatePlaybackCache(trackId)
        }

    suspend fun createLocalPlaylist(ownerKey: String, name: String): String =
        withContext(Dispatchers.IO) {
            if (authRepository.currentSession() == null) {
                authRepository.initialize()
            }
            ensureSystemPlaylists(ownerKey)
            val session = authRepository.currentSession()
            val userId = (session as? UserSession.Authenticated)?.profile?.userId
            val playlistId = UUID.randomUUID().toString()
            playlistDao.upsert(
                PlaylistEntity(
                    playlistId = playlistId,
                    ownerKey = ownerKey,
                    userId = userId,
                    name = name,
                    source = DataSource.LOCAL.dbValue,
                    isSynced = false,
                    updatedAt = System.currentTimeMillis(),
                ),
            )
            schedulePlaylistUpload()
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
                    isSynced = false,
                ),
            )
            playlistDao.markUnsynced(playlistId)
            schedulePlaylistUpload()
            evaluatePlaybackCache(video.videoId)
        }

    suspend fun addTracksToPlaylist(playlistId: String, videos: List<LibraryVideo>) =
        withContext(Dispatchers.IO) {
            if (videos.isEmpty()) return@withContext
            val ownerKey = authRepository.currentSession()?.ownerKey ?: return@withContext
            val userId = (authRepository.currentSession() as? UserSession.Authenticated)?.profile?.userId
            val existing = playlistTrackDao.getAllByPlaylist(playlistId)
            val existingIds = existing.mapTo(HashSet()) { it.trackId }
            var nextPosition = existing.size
            var changed = false
            for (video in videos) {
                if (video.videoId in existingIds) continue
                playbackHistoryRepository.depositPlayback(
                    video = video,
                    ownerKey = ownerKey,
                    userId = userId,
                )
                playlistTrackDao.upsert(
                    PlaylistTrackEntity(
                        playlistId = playlistId,
                        trackId = video.videoId,
                        position = nextPosition,
                        isSynced = false,
                    ),
                )
                existingIds.add(video.videoId)
                nextPosition += 1
                changed = true
                evaluatePlaybackCache(video.videoId, ownerKey)
            }
            if (changed) {
                playlistDao.markUnsynced(playlistId)
                schedulePlaylistUpload()
            }
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
                isSynced = false,
            ),
        )
        playlistDao.markUnsynced(playlist.playlistId)
        schedulePlaylistUpload()
        evaluatePlaybackCache(video.videoId, ownerKey)
    }

    private suspend fun removeTrackFromSystemPlaylist(
        ownerKey: String,
        systemType: String,
        trackId: String,
    ) = withContext(Dispatchers.IO) {
        val playlist = playlistDao.getSystemPlaylist(ownerKey, systemType) ?: return@withContext
        playlistTrackDao.deleteTrack(playlist.playlistId, trackId)
        playlistDao.markUnsynced(playlist.playlistId)
        schedulePlaylistUpload()
        evaluatePlaybackCache(trackId, ownerKey)
    }

    private suspend fun evaluatePlaybackCache(trackId: String, ownerKey: String? = null) {
        val key = ownerKey ?: authRepository.currentSession()?.ownerKey ?: return
        PlaybackCacheJanitor.evaluateTrack(appContext, key, trackId)
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
        schedulePlaylistUpload()
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
        userTrackMetadataDao.migrateOwnerKey(userOwnerKey, guestOwnerKey)

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
        userTrackMetadataDao.migrateOwnerKey(guestOwnerKey, userOwnerKey)

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

        syncAllPlaylistsFromRemote(userId, userOwnerKey)
        pullUserTrackMetadataFromRemote(userId, userOwnerKey)
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
        return systemPlaylists + customPlaylists
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

        val playlistsToSync = buildSet {
            addAll(playlistDao.getUnsyncedLocalByOwner(userOwnerKey).map { it.playlistId })
            addAll(
                playlistTrackDao.getUnsynced()
                    .mapNotNull { trackRef ->
                        playlistDao.getById(trackRef.playlistId)?.takeIf { playlist ->
                            playlist.ownerKey == userOwnerKey && playlist.isLocal()
                        }?.playlistId
                    },
            )
        }
        playlistsToSync.forEach { playlistId ->
            playlistDao.getById(playlistId)?.let { playlist ->
                uploadPlaylistToRemote(remoteClient, userId, playlist)
            }
        }

        userTrackMetadataDao.getUnsyncedByOwner(userOwnerKey).forEach { metadata ->
            syncTrackMetadataToRemote(userId, userOwnerKey, metadata)
        }
    }

    private suspend fun uploadPlaylistToRemote(
        remoteClient: SupabaseLibraryRemote,
        userId: String,
        playlist: PlaylistEntity,
    ) {
        remoteClient.upsertPlaylist(playlist.toPlaylistDto(userId))
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
        playlistDao.markSynced(playlist.playlistId)
        playlistTrackDao.markSyncedByPlaylist(playlist.playlistId)
    }

    private suspend fun syncAllPlaylistsFromRemote(userId: String, userOwnerKey: String) {
        val remoteClient = remote ?: return
        remoteClient.fetchAllPlaylists(userId).forEach { remotePlaylist ->
            mergePlaylistFromRemote(userId, userOwnerKey, remotePlaylist)
        }
    }

    private suspend fun mergePlaylistFromRemote(
        userId: String,
        userOwnerKey: String,
        remotePlaylist: PlaylistDto,
    ) {
        val remoteClient = remote ?: return
        val playlistId = remotePlaylist.playlistId
        val remoteUpdatedAt = remotePlaylist.updatedAtMillis()
        val localPlaylist = when {
            remotePlaylist.systemType != null ->
                playlistDao.getSystemPlaylist(userOwnerKey, remotePlaylist.systemType!!)
            else -> playlistDao.getById(playlistId)
        }

        val shouldApplyRemote = localPlaylist == null || remoteUpdatedAt >= localPlaylist.updatedAt

        if (shouldApplyRemote) {
            playlistDao.upsert(
                remotePlaylist.toPlaylistEntity(userOwnerKey, userId).copy(
                    isSynced = true,
                    updatedAt = remoteUpdatedAt,
                ),
            )
            if (localPlaylist != null && localPlaylist.playlistId != playlistId) {
                mergePlaylistTracks(localPlaylist.playlistId, playlistId)
                playlistTrackDao.deleteAllByPlaylist(localPlaylist.playlistId)
                playlistDao.deleteById(localPlaylist.playlistId)
            }
            val remoteTracks = if (remotePlaylist.systemType != null) {
                remoteClient.pullSystemPlaylistTracks(userId, remotePlaylist.systemType!!)
            } else {
                remoteClient.pullPlaylistTracks(playlistId)
            }
            val trackIds = remoteTracks.map { it.trackId }.distinct()
            remoteClient.pullTracksByIds(trackIds).forEach { trackDao.upsert(it) }
            remoteTracks.forEach { playlistTrackDao.upsert(it.copy(playlistId = playlistId, isSynced = true)) }
        } else {
            uploadPlaylistToRemote(remoteClient, userId, localPlaylist!!)
        }
    }

    private suspend fun pullUserTrackMetadataFromRemote(userId: String, userOwnerKey: String) {
        val remoteClient = remote ?: return
        val remoteMetadata = remoteClient.pullUserTrackMetadata(userId)
        remoteMetadata.forEach { dto ->
            val local = userTrackMetadataDao.getById(userOwnerKey, dto.trackId)
            val remoteUpdatedAt = dto.updatedAtMillis()
            if (local == null || remoteUpdatedAt >= local.updatedAt) {
                userTrackMetadataDao.upsert(
                    dto.toEntity(userOwnerKey).copy(isSynced = true),
                )
            }
        }
    }

    private fun LibraryVideoRow.toLibraryVideo() = LibraryVideo(
        videoId = trackId,
        title = title,
        channelName = primaryArtistName.orEmpty(),
        channelId = primaryArtistId,
        thumbnailUrl = thumbnailUrl,
        album = album,
        year = year,
        durationText = durationText,
        viewCountText = viewCountText,
        publishedTimeText = publishedText,
        watchedAt = lastPlayedAt,
        progressMs = progressMs,
    )

    private fun com.ytlite.player.data.local.model.LibrarySongRow.toLibraryVideo() = LibraryVideo(
        videoId = trackId,
        title = title,
        channelName = primaryArtistName.orEmpty(),
        channelId = primaryArtistId,
        thumbnailUrl = thumbnailUrl,
        album = album,
        year = year,
        watchedAt = lastActivityAt,
    )

    private suspend fun resolvePlaylistIdForAction(
        ownerKey: String,
        playlistId: String,
        systemType: String?,
    ): String? {
        if (systemType != null && systemType != PlaylistSystemType.HISTORY) {
            return playlistDao.getSystemPlaylist(ownerKey, systemType)?.playlistId ?: playlistId
        }
        return playlistId.takeIf { it.isNotBlank() && !it.startsWith("system:") }
            ?: playlistDao.getAllByOwner(ownerKey).firstOrNull { it.playlistId == playlistId }?.playlistId
    }

    private suspend fun findOwnedLocalPlaylist(
        playlistId: String,
        ownerKey: String,
    ): PlaylistEntity? {
        val playlist = playlistDao.getById(playlistId)
            ?: playlistDao.getAllByOwner(ownerKey).firstOrNull { it.playlistId == playlistId }
            ?: return null
        if (playlist.ownerKey != ownerKey || playlist.isYoutube()) return null
        if (playlist.systemType == PlaylistSystemType.HISTORY) return null
        return playlist
    }

    private suspend fun findOwnedLocalCustomPlaylist(
        playlistId: String,
        ownerKey: String,
    ): PlaylistEntity? {
        val playlist = playlistDao.getAllByOwner(ownerKey).firstOrNull { it.playlistId == playlistId }
            ?: return null
        if (playlist.ownerKey != ownerKey || playlist.systemType != null || playlist.isYoutube()) {
            return null
        }
        return playlist
    }

    private suspend fun findYoutubePlaylist(playlistId: String): PlaylistEntity? =
        youtubeRemote.getYoutubePlaylistsFlow().first()
            .firstOrNull { it.playlistId == playlistId }

    private fun applyPinOverlay(
        playlists: List<PlaylistEntity>,
        overlays: List<PlaylistPinOverlayEntity>,
    ): List<PlaylistEntity> {
        if (overlays.isEmpty()) return playlists
        val overlayMap = overlays.associateBy { it.playlistId }
        return playlists.map { playlist ->
            overlayMap[playlist.playlistId]?.let { overlay ->
                val effectiveUpdatedAt = when {
                    overlay.isPinned -> overlay.pinnedAt ?: playlist.updatedAt
                    overlay.unpinnedSortAt != null -> overlay.unpinnedSortAt
                    else -> playlist.updatedAt
                }
                playlist.copy(
                    isPinned = overlay.isPinned,
                    unpinnedSortAt = overlay.unpinnedSortAt,
                    pinnedAt = overlay.pinnedAt,
                    updatedAt = effectiveUpdatedAt,
                )
            } ?: playlist
        }
    }

    private fun orderPlaylistEntitiesByPin(playlists: List<PlaylistEntity>): List<PlaylistEntity> {
        val pinned = playlists.filter { it.isPinned }
            .sortedByDescending { it.pinnedAt ?: it.updatedAt }
        val unpinned = playlists.filter { !it.isPinned }
            .sortedByDescending { it.updatedAt }
        return pinned + unpinned
    }

    private fun schedulePlaylistUpload() {
        val session = authRepository.currentSession() as? UserSession.Authenticated ?: return
        repositoryScope.launch {
            uploadLocalDataToRemote(session.profile.userId, session.ownerKey)
        }
    }

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
