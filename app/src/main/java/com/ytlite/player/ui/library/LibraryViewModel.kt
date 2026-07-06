package com.ytlite.player.ui.library

import android.app.Application
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.ytlite.player.data.auth.AuthRepository
import com.ytlite.player.data.auth.UserSession
import com.ytlite.player.data.repository.LibraryRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update

class LibraryViewModel(
    application: Application,
    private val authRepository: AuthRepository = AuthRepository.getInstance(application),
    private val libraryRepository: LibraryRepository = LibraryRepository.getInstance(application),
) : ViewModel() {

    private val sessionFlow = authRepository.session

    val uiState: StateFlow<LibraryUiState> = sessionFlow
        .flatMapLatest { session ->
            val ownerKey = session?.ownerKey ?: return@flatMapLatest flowOf(LibraryUiState(isLoading = false))
            combine(
                libraryRepository.observeHistory(ownerKey),
                libraryRepository.observeWatchLaterCount(ownerKey),
                libraryRepository.observeLikedCount(ownerKey),
            ) { history, watchLaterCount, likedCount ->
                LibraryUiState(
                    session = session,
                    history = history,
                    watchLaterCount = watchLaterCount,
                    likedCount = likedCount,
                    isLoading = false,
                )
            }
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), LibraryUiState())

    fun refreshIfNeeded() {
        // Room flows auto-update; placeholder for pull-to-refresh later.
    }

    companion object {
        fun factory(application: Application): ViewModelProvider.Factory = viewModelFactory {
            initializer { LibraryViewModel(application) }
        }
    }
}
