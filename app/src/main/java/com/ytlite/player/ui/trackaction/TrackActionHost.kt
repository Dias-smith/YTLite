package com.ytlite.player.ui.trackaction

import android.app.Application
import android.widget.Toast
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
import com.ytlite.player.R
import com.ytlite.player.data.model.LibraryVideo
import com.ytlite.player.data.model.SubscriptionChannel
import com.ytlite.player.data.model.TrackMetadataSeed
import com.ytlite.player.download.DownloadRepository
import com.ytlite.player.ui.library.EditTrackMetadataDialog
import com.ytlite.player.ui.library.NewPlaylistDialog
import com.ytlite.player.ui.library.PlaylistPickerSheet
import com.ytlite.player.ui.library.PlaylistPickerViewModel

val LocalTrackMoreClick = compositionLocalOf<(TrackActionContext) -> Unit> { {} }
val LocalTrackDownloadClick = compositionLocalOf<(String) -> Unit> { {} }
val LocalDownloadedVideoIds = compositionLocalOf<Set<String>> { emptySet() }

data class TrackActionNavigation(
    val onGoToArtist: (SubscriptionChannel) -> Unit = {},
    val onGoToAlbum: (String) -> Unit = {},
)

@Composable
fun TrackActionHost(
    @Suppress("UNUSED_PARAMETER") navigation: TrackActionNavigation = TrackActionNavigation(),
    onRemoveFromQueue: ((String) -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    val application = LocalContext.current.applicationContext as Application
    val androidContext = LocalContext.current
    var trackActionContext by remember { mutableStateOf<TrackActionContext?>(null) }
    var editMetadataSeed by remember { mutableStateOf<TrackMetadataSeed?>(null) }
    var lyricsVideoId by remember { mutableStateOf<String?>(null) }
    var downloadVideoId by remember { mutableStateOf<String?>(null) }
    var playlistPickerVideo by remember { mutableStateOf<LibraryVideo?>(null) }
    var showNewPlaylistDialog by remember { mutableStateOf(false) }

    val playlistPickerViewModel: PlaylistPickerViewModel = viewModel(
        factory = PlaylistPickerViewModel.factory(application),
    )
    val playlistPickerState by playlistPickerViewModel.uiState.collectAsStateWithLifecycle()
    val downloadRepository = remember(application) {
        DownloadRepository.getInstance(application)
    }
    val downloadedVideoIds by downloadRepository.observeDownloadedVideoIds()
        .collectAsStateWithLifecycle(initialValue = emptySet())

    fun toast(message: String) {
        Toast.makeText(androidContext, message, Toast.LENGTH_SHORT).show()
    }

    val onTrackMoreClick: (TrackActionContext) -> Unit = { context ->
        trackActionContext = context
    }
    val onTrackDownloadClick: (String) -> Unit = { videoId ->
        if (videoId in downloadedVideoIds) {
            toast(androidContext.getString(R.string.download_video_already_downloaded))
        } else {
            downloadVideoId = videoId
        }
    }

    CompositionLocalProvider(
        LocalTrackMoreClick provides onTrackMoreClick,
        LocalTrackDownloadClick provides onTrackDownloadClick,
        LocalDownloadedVideoIds provides downloadedVideoIds,
    ) {
        content()
    }

    trackActionContext?.let { context ->
        TrackActionBottomSheet(
            context = context,
            onDismiss = { trackActionContext = null },
            onSaveToLibrary = { playlistPickerVideo = it.toLibraryVideo() },
            onEditMetadata = { trackContext ->
                editMetadataSeed = trackContext.toMetadataSeed()
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
            onSaved = {
                toast(androidContext.getString(R.string.edit_metadata_saved))
            },
        )
    }

    lyricsVideoId?.let { videoId ->
        LyricsBottomSheet(
            videoId = videoId,
            onDismiss = { lyricsVideoId = null },
        )
    }

    downloadVideoId?.let { videoId ->
        DownloadFormatBottomSheet(
            videoId = videoId,
            onDismiss = { downloadVideoId = null },
        )
    }

    playlistPickerVideo?.let { video ->
        PlaylistPickerSheet(
            playlists = playlistPickerState.playlists,
            subtitle = video.title,
            onDismiss = { playlistPickerVideo = null },
            onPlaylistSelected = { playlistId ->
                val playlistName = playlistPickerState.playlists
                    .firstOrNull { it.playlistId == playlistId }
                    ?.name
                    .orEmpty()
                playlistPickerViewModel.saveToPlaylist(playlistId, video) {
                    playlistPickerVideo = null
                    toast(
                        androidContext.getString(
                            R.string.toast_saved_to_playlist,
                            playlistName.ifBlank {
                                androidContext.getString(R.string.track_action_save_to_library)
                            },
                        ),
                    )
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
                    toast(androidContext.getString(R.string.toast_saved_to_playlist, name))
                }
            },
        )
    }
}
