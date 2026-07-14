package com.ytlite.player.ui.library

import android.app.Application
import androidx.compose.runtime.Immutable
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.ytlite.player.data.local.entity.PlaylistEntity
import com.ytlite.player.data.local.entity.PlaylistSystemType
import com.ytlite.player.data.local.model.PlaylistTrackDetailRow
import com.ytlite.player.data.model.PlaylistTrackSort
import com.ytlite.player.data.repository.LibraryRepository
import com.ytlite.player.data.repository.PlaylistTrackSorter
import com.ytlite.player.playback.QueueItem
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

@Immutable
data class PlaylistDetailUiState(
    val playlist: PlaylistEntity? = null,
    val tracks: List<PlaylistTrackDetailRow> = emptyList(),
    val coverUrls: List<String> = emptyList(),
    val trackCount: Int = 0,
    val totalDurationSeconds: Int = 0,
    val sort: PlaylistTrackSort = PlaylistTrackSort.MANUAL,
    val canEdit: Boolean = false,
    val canReorder: Boolean = false,
    val isLoading: Boolean = true,
)

@OptIn(ExperimentalCoroutinesApi::class)
class PlaylistDetailViewModel(
    private val playlistId: String,
    private val ownerKey: String,
    private val systemType: String?,
    private val libraryRepository: LibraryRepository,
) : ViewModel() {

    private val playlistState = MutableStateFlow<PlaylistEntity?>(null)
    private val sortState = MutableStateFlow(PlaylistTrackSort.MANUAL)

    init {
        viewModelScope.launch {
            playlistState.value = libraryRepository.getPlaylistById(
                playlistId = playlistId,
                ownerKey = ownerKey,
                systemType = systemType,
            )
        }
    }

    val uiState: StateFlow<PlaylistDetailUiState> = playlistState.flatMapLatest { playlist ->
        if (playlist == null) {
            flowOf(PlaylistDetailUiState(isLoading = true))
        } else {
            combine(
                libraryRepository.observePlaylistTrackDetails(playlist.playlistId),
                sortState,
            ) { tracks, currentSort ->
                val displayed = PlaylistTrackSorter.sort(tracks, currentSort)
                PlaylistDetailUiState(
                    playlist = playlist,
                    tracks = displayed,
                    coverUrls = buildCoverUrls(playlist, tracks),
                    trackCount = tracks.size,
                    totalDurationSeconds = tracks.sumOf { it.durationSeconds },
                    sort = currentSort,
                    canEdit = playlist.isLocal() && playlist.systemType == null,
                    canReorder = playlist.isLocal() && currentSort == PlaylistTrackSort.MANUAL,
                    isLoading = false,
                )
            }
        }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), PlaylistDetailUiState())

    fun setSort(sort: PlaylistTrackSort) {
        val playlist = playlistState.value
        if (playlist?.isYoutube() == true && sort == PlaylistTrackSort.MANUAL) {
            return
        }
        sortState.value = sort
    }

    fun commitTrackOrder(orderedTrackIds: List<String>) {
        viewModelScope.launch {
            val playlist = playlistState.value ?: return@launch
            if (!playlist.isLocal()) return@launch
            libraryRepository.reorderPlaylistTracks(
                playlistId = playlist.playlistId,
                ownerKey = ownerKey,
                orderedTrackIds = orderedTrackIds,
            )
        }
    }

    fun renamePlaylist(name: String, onDone: (Boolean) -> Unit) {
        viewModelScope.launch {
            val success = libraryRepository.renameLocalPlaylist(
                playlistId = playlistId,
                ownerKey = ownerKey,
                name = name,
            )
            if (success) {
                playlistState.value = libraryRepository.getPlaylistById(
                    playlistId = playlistId,
                    ownerKey = ownerKey,
                    systemType = systemType,
                )
            }
            onDone(success)
        }
    }

    suspend fun loadQueueItems(): List<QueueItem> {
        val displayed = uiState.value.tracks
        if (displayed.isNotEmpty()) {
            return displayed.map { track ->
                QueueItem(
                    videoId = track.trackId,
                    title = track.title,
                    channelName = track.primaryArtistName.orEmpty(),
                    thumbnailUrl = track.thumbnailUrl,
                    durationText = track.durationText,
                    album = track.album,
                    year = track.year,
                    channelId = track.primaryArtistId,
                )
            }
        }
        return libraryRepository.getPlaylistQueueItems(
            ownerKey = ownerKey,
            playlistId = playlistId,
            systemType = systemType,
        )
    }

    private fun buildCoverUrls(
        playlist: PlaylistEntity,
        tracks: List<PlaylistTrackDetailRow>,
    ): List<String> {
        playlist.coverUrlOrPath?.takeIf { it.isNotBlank() }?.let { return listOf(it) }
        return tracks.mapNotNull { it.thumbnailUrl.takeIf { url -> url.isNotBlank() } }.take(4)
    }

    companion object {
        fun factory(
            application: Application,
            playlistId: String,
            ownerKey: String,
            systemType: String? = null,
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                PlaylistDetailViewModel(
                    playlistId = playlistId,
                    ownerKey = ownerKey,
                    systemType = systemType,
                    libraryRepository = LibraryRepository.getInstance(application),
                )
            }
        }
    }
}

fun PlaylistEntity.isLikedSystemPlaylist(): Boolean =
    systemType == PlaylistSystemType.FAVORITES

fun PlaylistEntity.isWatchLaterSystemPlaylist(): Boolean =
    systemType == PlaylistSystemType.WATCH_LATER
