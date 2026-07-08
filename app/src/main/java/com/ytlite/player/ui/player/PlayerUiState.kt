package com.ytlite.player.ui.player

import androidx.compose.runtime.Immutable
import com.ytlite.player.data.model.VideoItem
import com.ytlite.player.data.model.VideoPlayback

@Immutable
data class PlayerUiState(
    val playback: VideoPlayback? = null,
    val selectedStreamUrl: String? = null,
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val isDescriptionExpanded: Boolean = false,
    val surfaceMode: PlayerSurfaceMode = PlayerSurfaceMode.Auto,
    val upNextItems: List<VideoItem> = emptyList(),
    val upNextLoading: Boolean = false,
    val isPlaylistPickerVisible: Boolean = false,
    val showNewPlaylistDialog: Boolean = false,
    val lastExtractMessage: org.json.JSONObject? = null,
)
