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
import com.ytlite.player.data.model.LibrarySort
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

    init {
        viewModelScope.launch { authRepository.initialize() }
    }

    val uiState: StateFlow<LibraryUiState> = combine(
        sessionFlow,
        selectedFilter,
        sort,
        viewMode,
    ) { session, filter, currentSort, mode ->
        LibraryQuery(session, filter, currentSort, mode)
    }.flatMapLatest { query ->
        val session = query.session
            ?: return@flatMapLatest flowOf(LibraryUiState(isLoading = true))
        libraryRepository.observeLibraryItems(
            ownerKey = session.ownerKey,
            filter = query.filter,
            sort = query.sort,
            isAuthenticated = session is UserSession.Authenticated,
        ).map { items ->
            LibraryUiState(
                session = session,
                items = items,
                selectedFilter = query.filter,
                sort = query.sort,
                viewMode = query.mode,
                visibleChips = LibraryItemMapper.visibleChips(session),
                isLoading = false,
            )
        }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), LibraryUiState())

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
        selectedFilter.value = chip
    }

    fun toggleSort() {
        sort.update {
            if (it == LibrarySort.RECENT_ACTIVITY) LibrarySort.RECENTLY_SAVED else LibrarySort.RECENT_ACTIVITY
        }
    }

    fun toggleViewMode() {
        viewMode.update {
            if (it == LibraryViewMode.LIST) LibraryViewMode.GRID else LibraryViewMode.LIST
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
            val ownerKey = authRepository.currentSession()?.ownerKey ?: return@launch
            libraryRepository.createLocalPlaylist(ownerKey, name)
        }
    }

    private data class LibraryQuery(
        val session: UserSession?,
        val filter: LibraryFilterChip,
        val sort: LibrarySort,
        val mode: LibraryViewMode,
    )

    companion object {
        fun factory(application: Application): ViewModelProvider.Factory = viewModelFactory {
            initializer { LibraryViewModel(application) }
        }
    }
}
