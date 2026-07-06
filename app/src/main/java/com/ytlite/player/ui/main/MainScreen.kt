package com.ytlite.player.ui.main

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Subscriptions
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Subscriptions
import androidx.compose.material.icons.outlined.VideoLibrary
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import com.ytlite.player.R
import com.ytlite.player.playback.GlobalPlaybackUiState
import com.ytlite.player.ui.home.HomeScreen
import com.ytlite.player.ui.library.LibraryScreen
import com.ytlite.player.ui.playback.MiniPlayerBar
import com.ytlite.player.ui.shorts.ShortsScreen
import com.ytlite.player.ui.subscriptions.SubscriptionsScreen
import kotlinx.coroutines.launch

private enum class MainTab(
    val labelRes: Int,
    val selectedIcon: ImageVector,
    val unselectedIcon: ImageVector,
) {
    Home(
        labelRes = R.string.nav_home,
        selectedIcon = Icons.Filled.Home,
        unselectedIcon = Icons.Outlined.Home,
    ),
    Shorts(
        labelRes = R.string.nav_shorts,
        selectedIcon = Icons.Filled.Home,
        unselectedIcon = Icons.Outlined.Home,
    ),
    Subscriptions(
        labelRes = R.string.nav_subscriptions,
        selectedIcon = Icons.Filled.Subscriptions,
        unselectedIcon = Icons.Outlined.Subscriptions,
    ),
    Library(
        labelRes = R.string.nav_library,
        selectedIcon = Icons.Filled.VideoLibrary,
        unselectedIcon = Icons.Outlined.VideoLibrary,
    ),
}

@Composable
fun MainScreen(
    onVideoClick: (String) -> Unit,
    globalPlaybackState: GlobalPlaybackUiState,
    onMiniPlayerOpen: () -> Unit,
    onMiniPlayerTogglePlayPause: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var selectedTab by rememberSaveable { mutableIntStateOf(MainTab.Home.ordinal) }
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    val signInComingSoon = stringResource(R.string.sign_in_coming_soon)

    val onSignInClick: () -> Unit = {
        scope.launch {
            snackbarHostState.showSnackbar(signInComingSoon)
        }
    }

    Scaffold(
        modifier = modifier.fillMaxSize(),
        snackbarHost = { SnackbarHost(snackbarHostState) },
        bottomBar = {
            Column {
                if (globalPlaybackState.showMiniPlayer) {
                    MiniPlayerBar(
                        state = globalPlaybackState,
                        onOpenPlayer = onMiniPlayerOpen,
                        onTogglePlayPause = onMiniPlayerTogglePlayPause,
                    )
                }
                NavigationBar {
                    MainTab.entries.forEachIndexed { index, tab ->
                        NavigationBarItem(
                            selected = selectedTab == index,
                            onClick = { selectedTab = index },
                            icon = {
                                Icon(
                                    imageVector = if (selectedTab == index) {
                                        tab.selectedIcon
                                    } else {
                                        tab.unselectedIcon
                                    },
                                    contentDescription = stringResource(tab.labelRes),
                                )
                            },
                            label = { Text(text = stringResource(tab.labelRes)) },
                        )
                    }
                }
            }
        },
    ) { innerPadding ->
        when (MainTab.entries[selectedTab]) {
            MainTab.Home -> HomeScreen(
                onVideoClick = onVideoClick,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding),
            )
            MainTab.Shorts -> ShortsScreen(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding),
            )
            MainTab.Subscriptions -> SubscriptionsScreen(
                onSignInClick = onSignInClick,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding),
            )
            MainTab.Library -> LibraryScreen(
                onSignInClick = onSignInClick,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding),
            )
        }
    }
}
