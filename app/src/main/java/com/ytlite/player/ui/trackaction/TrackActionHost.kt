package com.ytlite.player.ui.trackaction

import android.app.Application
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.ytlite.player.data.model.LibraryVideo
import com.ytlite.player.data.model.SubscriptionChannel
import com.ytlite.player.ui.library.EditTrackMetadataDialog
import com.ytlite.player.data.model.TrackMetadataSeed
import com.ytlite.player.ui.trackaction.toMetadataSeed
import com.ytlite.player.ui.library.NewPlaylistDialog
import com.ytlite.player.ui.library.PlaylistPickerSheet
import com.ytlite.player.ui.library.PlaylistPickerViewModel

val LocalTrackMoreClick = compositionLocalOf<(TrackActionContext) -> Unit> { {} }

data class TrackActionNavigation(
    val onGoToArtist: (SubscriptionChannel) -> Unit = {},
    val onGoToAlbum: (String) -> Unit = {},
)

@Composable
fun TrackActionHost(
    navigation: TrackActionNavigation,
    onRemoveFromQueue: ((String) -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    val application = LocalContext.current.applicationContext as Application
    var trackActionContext by remember { mutableStateOf<TrackActionContext?>(null) }
    var editMetadataSeed by remember { mutableStateOf<TrackMetadataSeed?>(null) }
    var lyricsVideoId by remember { mutableStateOf<String?>(null) }
    var playlistPickerVideo by remember { mutableStateOf<LibraryVideo?>(null) }
    var showNewPlaylistDialog by remember { mutableStateOf(false) }

    val playlistPickerViewModel: PlaylistPickerViewModel = viewModel(
        factory = PlaylistPickerViewModel.factory(application),
    )
    val playlistPickerState by playlistPickerViewModel.uiState.collectAsStateWithLifecycle()

    val onTrackMoreClick: (TrackActionContext) -> Unit = { context ->
        trackActionContext = context
    }

    CompositionLocalProvider(LocalTrackMoreClick provides onTrackMoreClick) {
        content()
    }

    trackActionContext?.let { context ->
        TrackActionBottomSheet(
            context = context,
            onDismiss = { trackActionContext = null },
            onSaveToLibrary = { playlistPickerVideo = it.toLibraryVideo() },
            onEditMetadata = { context ->
                editMetadataSeed = context.toMetadataSeed()
            },
            onGoToAlbum = { album -> navigation.onGoToAlbum(album) },
            onGoToArtist = { channelId, channelName ->
                navigation.onGoToArtist(
                    SubscriptionChannel(
                        channelId = channelId,
                        title = channelName,
                        handle = null,
                        avatarUrl = "",
                        subscriberCountText = null,
                        description = null,
                    ),
                )
            },
            onViewLyrics = { videoId -> lyricsVideoId = videoId },
            onRemoveFromQueue = if (context.showRemoveFromQueue) {
                { onRemoveFromQueue?.invoke(context.videoId) }
            } else {
                null
            },
        )
    }

    editMetadataSeed?.let { seed ->
        EditTrackMetadataDialog(
            trackId = seed.trackId,
            seed = seed,
            onDismiss = { editMetadataSeed = null },
        )
    }

    lyricsVideoId?.let { videoId ->
        LyricsBottomSheet(
            videoId = videoId,
            onDismiss = { lyricsVideoId = null },
        )
    }

    playlistPickerVideo?.let { video ->
        PlaylistPickerSheet(
            playlists = playlistPickerState.playlists,
            subtitle = video.title,
            onDismiss = { playlistPickerVideo = null },
            onPlaylistSelected = { playlistId ->
                playlistPickerViewModel.saveToPlaylist(playlistId, video) {
                    playlistPickerVideo = null
                }
            },
            onCreatePlaylist = { showNewPlaylistDialog = true },
        )
    }

    if (showNewPlaylistDialog && playlistPickerVideo != null) {
        val video = playlistPickerVideo!!
        NewPlaylistDialog(
            onDismiss = { showNewPlaylistDialog = false },
            onConfirm = { name ->
                playlistPickerViewModel.createAndSave(name, video) {
                    showNewPlaylistDialog = false
                    playlistPickerVideo = null
                }
            },
        )
    }
}
