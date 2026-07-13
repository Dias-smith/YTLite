package com.ytlite.player.ui.library

import com.ytlite.player.data.model.VideoItem
import com.ytlite.player.playback.QueueItem
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier

@Composable
fun LibraryScreen(
    onVideoClick: (VideoItem) -> Unit,
    onSignInClick: () -> Unit,
    onSignOutClick: () -> Unit,
    onNavigateHomeTab: () -> Unit,
    onPlayPlaylist: (List<QueueItem>, Int, String) -> Unit,
    onTogglePlayPause: () -> Unit,
    pendingAlbumName: String? = null,
    onPendingAlbumConsumed: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    LaunchedEffect(pendingAlbumName) {
        // consumed inside LibraryNavHost
    }
    LibraryNavHost(
        onVideoClick = onVideoClick,
        onSignInClick = onSignInClick,
        onSignOutClick = onSignOutClick,
        onNavigateHomeTab = onNavigateHomeTab,
        onPlayPlaylist = onPlayPlaylist,
        onTogglePlayPause = onTogglePlayPause,
        pendingAlbumName = pendingAlbumName,
        onPendingAlbumConsumed = onPendingAlbumConsumed,
        modifier = modifier,
    )
}
