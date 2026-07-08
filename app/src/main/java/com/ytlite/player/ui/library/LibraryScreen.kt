package com.ytlite.player.ui.library

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

@Composable
fun LibraryScreen(
    onVideoClick: (String) -> Unit,
    onSignInClick: () -> Unit,
    onSignOutClick: () -> Unit,
    onNavigateHomeTab: () -> Unit,
    modifier: Modifier = Modifier,
) {
    LibraryNavHost(
        onVideoClick = onVideoClick,
        onSignInClick = onSignInClick,
        onSignOutClick = onSignOutClick,
        onNavigateHomeTab = onNavigateHomeTab,
        modifier = modifier,
    )
}
