package com.ytlite.player.ui.player

import androidx.compose.runtime.Immutable
import com.ytlite.player.data.model.LibraryVideo
import com.ytlite.player.data.model.VideoItem
import com.ytlite.player.data.model.VideoPlayback

enum class PlayerListTab {
    UpNext,
    Recommend,
}

@Immutable
data class PlayerUiState(
    val playback: VideoPlayback? = null,
    val selectedStreamUrl: String? = null,
    val isLoading: Boolean = false,
    val isExtracting: Boolean = false,
    val errorMessage: String? = null,
    val isDescriptionExpanded: Boolean = false,
    val surfaceMode: PlayerSurfaceMode = PlayerSurfaceMode.Video,
    /** @deprecated Prefer reading PlayQueue for Up next tab; kept for enrich lookups. */
    val upNextItems: List<VideoItem> = emptyList(),
    val recommendedItems: List<VideoItem> = emptyList(),
    val recommendLoading: Boolean = false,
    val upNextLoading: Boolean = false,
    val selectedListTab: PlayerListTab = PlayerListTab.UpNext,
    val isPlaylistPickerVisible: Boolean = false,
    val showNewPlaylistDialog: Boolean = false,
    /** When non-null, playlist picker saves this batch instead of the current track. */
    val playlistSaveItems: List<LibraryVideo>? = null,
    val lastExtractMessage: org.json.JSONObject? = null,
)
