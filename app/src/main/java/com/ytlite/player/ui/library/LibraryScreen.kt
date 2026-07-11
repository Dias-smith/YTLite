package com.ytlite.player.ui.library

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier

@Composable
fun LibraryScreen(
    onVideoClick: (String) -> Unit,
    onSignInClick: () -> Unit,
    onSignOutClick: () -> Unit,
    onNavigateHomeTab: () -> Unit,
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
        pendingAlbumName = pendingAlbumName,
        onPendingAlbumConsumed = onPendingAlbumConsumed,
        modifier = modifier,
    )
}
