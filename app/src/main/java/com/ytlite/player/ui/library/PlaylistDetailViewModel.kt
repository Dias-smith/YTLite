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
import com.ytlite.player.data.model.DataSource
import com.ytlite.player.data.repository.LibraryRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.concurrent.TimeUnit

@Immutable
data class PlaylistDetailUiState(
    val playlist: PlaylistEntity? = null,
    val tracks: List<PlaylistTrackDetailRow> = emptyList(),
    val coverUrls: List<String> = emptyList(),
    val statsText: String = "",
    val isLoading: Boolean = true,
)

class PlaylistDetailViewModel(
    private val playlistId: String,
    private val ownerKey: String,
    private val libraryRepository: LibraryRepository,
) : ViewModel() {

    private val playlistState = MutableStateFlow<PlaylistEntity?>(null)

    init {
        viewModelScope.launch {
            playlistState.value = libraryRepository.getPlaylistById(playlistId, ownerKey)
        }
    }

    val uiState: StateFlow<PlaylistDetailUiState> = combine(
        playlistState,
        libraryRepository.observePlaylistTrackDetails(playlistId),
    ) { playlist, tracks ->
        if (playlist == null) {
            PlaylistDetailUiState(isLoading = true)
        } else {
            PlaylistDetailUiState(
                playlist = playlist,
                tracks = tracks,
                coverUrls = buildCoverUrls(playlist, tracks),
                statsText = buildStatsText(playlist, tracks),
                isLoading = false,
            )
        }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), PlaylistDetailUiState())

    fun cloneToLocal() {
        viewModelScope.launch {
            libraryRepository.importYoutubePlaylistToLocal(playlistId, ownerKey)
        }
    }

    private fun buildCoverUrls(
        playlist: PlaylistEntity,
        tracks: List<PlaylistTrackDetailRow>,
    ): List<String> {
        playlist.coverUrlOrPath?.takeIf { it.isNotBlank() }?.let { return listOf(it) }
        return tracks.mapNotNull { it.thumbnailUrl.takeIf { url -> url.isNotBlank() } }.take(4)
    }

    private fun buildStatsText(
        playlist: PlaylistEntity,
        tracks: List<PlaylistTrackDetailRow>,
    ): String {
        val totalSeconds = tracks.sumOf { it.durationSeconds }
        val duration = if (totalSeconds > 0) {
            val minutes = totalSeconds / 60
            val seconds = totalSeconds % 60
            "$minutes mins $seconds secs"
        } else {
            "${tracks.size} songs"
        }
        val updated = formatRelativeTime(playlist.updatedAt)
        return "$duration • $updated"
    }

    private fun formatRelativeTime(timestamp: Long): String {
        val now = System.currentTimeMillis()
        val diff = now - timestamp
        val days = TimeUnit.MILLISECONDS.toDays(diff)
        return when {
            days < 1 -> "today"
            days < 30 -> "${days}d ago"
            days < 365 -> "${days / 30} mo ago"
            else -> DateTimeFormatter.ofPattern("MMM yyyy", Locale.getDefault())
                .format(Instant.ofEpochMilli(timestamp).atZone(ZoneId.systemDefault()))
        }
    }

    companion object {
        fun factory(
            application: Application,
            playlistId: String,
            ownerKey: String,
        ): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                PlaylistDetailViewModel(
                    playlistId = playlistId,
                    ownerKey = ownerKey,
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
