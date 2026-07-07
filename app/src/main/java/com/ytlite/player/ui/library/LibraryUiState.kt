package com.ytlite.player.ui.library

import androidx.compose.runtime.Immutable
import com.ytlite.player.data.auth.UserSession
import com.ytlite.player.data.local.entity.PlaylistEntity
import com.ytlite.player.data.model.LibraryVideo

@Immutable
data class LibraryUiState(
    val session: UserSession = UserSession.Guest(guestId = ""),
    val history: List<LibraryVideo> = emptyList(),
    val unifiedPlaylists: List<PlaylistEntity> = emptyList(),
    val isLoading: Boolean = true,
)
