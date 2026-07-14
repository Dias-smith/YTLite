package com.ytlite.player.ui.library

import android.app.Application
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.ytlite.player.data.auth.AuthRepository
import com.ytlite.player.data.auth.UserSession
import com.ytlite.player.data.model.LibraryFilterChip
import com.ytlite.player.data.model.LibraryItem
import com.ytlite.player.data.model.LibrarySort
import com.ytlite.player.data.model.LibraryVideo
import com.ytlite.player.data.model.LibraryViewMode
import com.ytlite.player.data.repository.LibraryItemMapper
import com.ytlite.player.data.repository.LibraryRepository
import com.ytlite.player.data.youtube.YoutubeDiagnostics
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class LibraryViewModel(
    application: Application,
    private val authRepository: AuthRepository = AuthRepository.getInstance(application),
    private val libraryRepository: LibraryRepository = LibraryRepository.getInstance(application),
) : ViewModel() {

    private val sessionFlow = authRepository.session
    private val selectedFilter = MutableStateFlow(LibraryFilterChip.PLAYLISTS)
    private val sort = MutableStateFlow(LibrarySort.RECENT_ACTIVITY)
    private val viewMode = MutableStateFlow(LibraryViewMode.LIST)
    private val isPlaylistReorderMode = MutableStateFlow(false)
    private val isSelectionMode = MutableStateFlow(false)
    private val selectedIds = MutableStateFlow<Set<String>>(emptySet())
    private val pendingSnackbar = MutableStateFlow<String?>(null)

    init {
        viewModelScope.launch { authRepository.initialize() }
    }

    val uiState: StateFlow<LibraryUiState> = combine(
        sessionFlow,
        selectedFilter,
        sort,
        viewMode,
        isPlaylistReorderMode,
    ) { session, filter, currentSort, mode, reorderMode ->
        LibraryQuery(session, filter, currentSort, mode, reorderMode)
    }.flatMapLatest { query ->
        val session = query.session
            ?: return@flatMapLatest flowOf(LibraryUiState(isLoading = true))
        val effectiveSort = if (query.reorderMode && query.filter == LibraryFilterChip.PLAYLISTS) {
            LibrarySort.CUSTOM
        } else {
            query.sort
        }
        combine(
            libraryRepository.observeLibraryItems(
                ownerKey = session.ownerKey,
                filter = query.filter,
                sort = effectiveSort,
                isAuthenticated = session is UserSession.Authenticated,
            ),
            isSelectionMode,
            selectedIds,
            pendingSnackbar,
        ) { items, selectionMode, ids, snackbar ->
            LibraryUiState(
                session = session,
                items = items,
                selectedFilter = query.filter,
                sort = query.sort,
                viewMode = query.mode,
                visibleChips = LibraryItemMapper.visibleChips(session),
                isLoading = false,
                isPlaylistReorderMode = query.reorderMode,
                isSelectionMode = selectionMode,
                selectedIds = ids,
                pendingSnackbar = snackbar,
            )
        }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), LibraryUiState(isLoading = true))

    fun refreshIfNeeded() {
        viewModelScope.launch {
            authRepository.initialize()
            val session = authRepository.currentSession() ?: return@launch
            libraryRepository.ensureLocalLibraryReady(session.ownerKey)
            if (session is UserSession.Authenticated) {
                libraryRepository.refreshYoutubePlaylists()
            } else {
                YoutubeDiagnostics.logPlaylistsFetchOutcome(
                    step = "Playlists/VM",
                    outcome = "skipped",
                    detail = "not Authenticated",
                )
            }
        }
    }

    fun selectFilter(chip: LibraryFilterChip) {
        if (chip != LibraryFilterChip.PLAYLISTS) {
            isPlaylistReorderMode.value = false
        }
        exitSelectionMode()
        selectedFilter.value = chip
    }

    fun setSort(next: LibrarySort) {
        if (next == LibrarySort.CUSTOM) return
        sort.value = next
        isPlaylistReorderMode.value = false
    }

    fun toggleSort() {
        sort.update {
            if (it == LibrarySort.RECENT_ACTIVITY) LibrarySort.RECENTLY_SAVED else LibrarySort.RECENT_ACTIVITY
        }
    }

    fun toggleViewMode() {
        if (isPlaylistReorderMode.value) return
        viewMode.update {
            if (it == LibraryViewMode.LIST) LibraryViewMode.GRID else LibraryViewMode.LIST
        }
    }

    fun enterPlaylistReorderMode() {
        viewModelScope.launch {
            val session = authRepository.currentSession() ?: return@launch
            exitSelectionMode()
            val currentItems = uiState.value.items.filterIsInstance<LibraryItem.Playlist>()
            if (sort.value != LibrarySort.CUSTOM) {
                libraryRepository.seedDisplayOrderFromCurrent(session.ownerKey, currentItems)
            }
            viewMode.value = LibraryViewMode.LIST
            isPlaylistReorderMode.value = true
        }
    }

    fun exitPlaylistReorderMode() {
        isPlaylistReorderMode.value = false
        sort.value = LibrarySort.CUSTOM
    }

    fun commitPlaylistOrder(playlists: List<LibraryItem.Playlist>) {
        viewModelScope.launch {
            val session = authRepository.currentSession() ?: return@launch
            libraryRepository.seedDisplayOrderFromCurrent(session.ownerKey, playlists)
        }
    }

    fun enterSelectionMode() {
        if (!LibraryUiState.supportsMultiSelect(selectedFilter.value)) return
        if (isPlaylistReorderMode.value) return
        isSelectionMode.value = true
        selectedIds.value = emptySet()
    }

    fun exitSelectionMode() {
        isSelectionMode.value = false
        selectedIds.value = emptySet()
    }

    fun toggleSelection(id: String) {
        if (!isSelectionMode.value) return
        selectedIds.update { current ->
            if (id in current) current - id else current + id
        }
    }

    fun clearSnackbar() {
        pendingSnackbar.value = null
    }

    fun showSnackbar(message: String) {
        pendingSnackbar.value = message
    }

    fun selectedSongsAsLibraryVideos(): List<LibraryVideo> {
        val ids = selectedIds.value
        return uiState.value.items
            .filterIsInstance<LibraryItem.Song>()
            .filter { it.id in ids }
            .map { song ->
                LibraryVideo(
                    videoId = song.videoId,
                    title = song.title,
                    channelName = song.artistName.ifBlank { song.subtitle },
                    channelId = song.channelId,
                    thumbnailUrl = song.coverUrl.orEmpty(),
                    album = song.album,
                    year = song.year,
                )
            }
    }

    fun deleteSelected(onDone: (skipped: Boolean) -> Unit) {
        viewModelScope.launch {
            val session = authRepository.currentSession() ?: return@launch
            val state = uiState.value
            val ids = selectedIds.value
            if (ids.isEmpty()) return@launch
            when (state.selectedFilter) {
                LibraryFilterChip.SONGS -> {
                    libraryRepository.removeTracksFromLocalLibrary(session.ownerKey, ids.toList())
                    exitSelectionMode()
                    onDone(false)
                }
                LibraryFilterChip.PLAYLISTS -> {
                    val deleted = libraryRepository.deleteLocalPlaylists(session.ownerKey, ids.toList())
                    val skipped = deleted < ids.size
                    exitSelectionMode()
                    onDone(skipped)
                }
                else -> onDone(false)
            }
        }
    }

    fun addSelectedSongsToPlaylist(playlistId: String, onDone: () -> Unit) {
        viewModelScope.launch {
            val videos = selectedSongsAsLibraryVideos()
            if (videos.isEmpty()) return@launch
            libraryRepository.addTracksToPlaylist(playlistId, videos)
            exitSelectionMode()
            onDone()
        }
    }

    fun createPlaylistAndAddSelected(name: String, onDone: () -> Unit) {
        viewModelScope.launch {
            authRepository.initialize()
            val ownerKey = authRepository.currentSession()?.ownerKey ?: return@launch
            val videos = selectedSongsAsLibraryVideos()
            val playlistId = libraryRepository.createLocalPlaylist(ownerKey, name)
            if (videos.isNotEmpty()) {
                libraryRepository.addTracksToPlaylist(playlistId, videos)
            }
            exitSelectionMode()
            onDone()
        }
    }

    fun cloneYoutubePlaylistToLocal(playlistId: String) {
        viewModelScope.launch {
            val ownerKey = authRepository.currentSession()?.ownerKey ?: return@launch
            libraryRepository.importYoutubePlaylistToLocal(playlistId, ownerKey)
        }
    }

    fun createPlaylist(name: String) {
        viewModelScope.launch {
            authRepository.initialize()
            val ownerKey = authRepository.currentSession()?.ownerKey ?: return@launch
            libraryRepository.createLocalPlaylist(ownerKey, name)
        }
    }

    private data class LibraryQuery(
        val session: UserSession?,
        val filter: LibraryFilterChip,
        val sort: LibrarySort,
        val mode: LibraryViewMode,
        val reorderMode: Boolean,
    )

    companion object {
        fun factory(application: Application): ViewModelProvider.Factory = viewModelFactory {
            initializer { LibraryViewModel(application) }
        }
    }
}
