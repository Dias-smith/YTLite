package com.ytlite.player.ui.main

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Subscriptions
import androidx.compose.material.icons.filled.VideoLibrary
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.Subscriptions
import androidx.compose.material.icons.outlined.VideoLibrary
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.ytlite.player.R
import com.ytlite.player.data.auth.UserSession
import com.ytlite.player.data.model.VideoItem
import com.ytlite.player.data.model.SubscriptionChannel
import com.ytlite.player.playback.GlobalPlaybackUiState
import com.ytlite.player.playback.QueueItem
import com.ytlite.player.ui.auth.AuthViewModel
import com.ytlite.player.ui.auth.YoutubeWebLoginScreen
import com.ytlite.player.ui.auth.rememberGoogleSignInLauncher
import com.ytlite.player.data.network.YoutubeCookieJar
import com.ytlite.player.ui.home.HomeScreen
import com.ytlite.player.ui.library.AccountSwitcherSheet
import com.ytlite.player.ui.library.LibraryScreen
import com.ytlite.player.ui.playback.MiniPlayerBar
import com.ytlite.player.ui.search.SearchScreen
import com.ytlite.player.ui.shorts.ShortsScreen
import com.ytlite.player.ui.subscriptions.ChannelVideosScreen
import com.ytlite.player.ui.subscriptions.SubscriptionChannelsScreen
import com.ytlite.player.ui.subscriptions.SubscriptionsScreen
import com.ytlite.player.ui.subscriptions.YoutubePlaylistItemsScreen
import com.ytlite.player.ui.subscriptions.YoutubePlaylistNav
import com.ytlite.player.ui.subscriptions.YoutubePlaylistsListScreen
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
        selectedIcon = Icons.Filled.PlayArrow,
        unselectedIcon = Icons.Outlined.PlayArrow,
    ),
    Search(
        labelRes = R.string.nav_search,
        selectedIcon = Icons.Filled.Search,
        unselectedIcon = Icons.Outlined.Search,
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

private fun Modifier.mainTabPadding(
    innerPadding: PaddingValues,
    applyTopInset: Boolean,
): Modifier = padding(
    top = if (applyTopInset) innerPadding.calculateTopPadding() else 0.dp,
    bottom = innerPadding.calculateBottomPadding(),
)

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun MainScreen(
    onVideoClick: (VideoItem) -> Unit,
    globalPlaybackState: GlobalPlaybackUiState,
    onMiniPlayerOpenPlayer: (String) -> Unit,
    onMiniPlayerTogglePlayPause: () -> Unit,
    onMiniPlayerSkipNext: () -> Unit,
    onPlayPlaylist: (List<QueueItem>, Int, String) -> Unit,
    authViewModel: AuthViewModel,
    pendingArtistChannel: SubscriptionChannel? = null,
    onPendingArtistConsumed: () -> Unit = {},
    pendingAlbumName: String? = null,
    onPendingAlbumConsumed: () -> Unit = {},
    switchToLibraryTab: Boolean = false,
    onSwitchToLibraryTabConsumed: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    var selectedTabName by rememberSaveable { mutableStateOf(MainTab.Home.name) }
    val selectedTab = MainTab.entries.find { it.name == selectedTabName } ?: MainTab.Home
    var showSubscriptionChannels by rememberSaveable { mutableStateOf(false) }
    var showYoutubePlaylists by rememberSaveable { mutableStateOf(false) }
    var selectedChannel by remember { mutableStateOf<SubscriptionChannel?>(null) }
    var selectedYoutubePlaylist by remember { mutableStateOf<YoutubePlaylistNav?>(null) }
    var showAccountSwitcher by rememberSaveable { mutableStateOf(false) }
    var showYoutubeWebLogin by rememberSaveable { mutableStateOf(false) }
    var youtubeCookieSessionEpoch by rememberSaveable { mutableStateOf(0) }
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    val signInComingSoon = stringResource(R.string.sign_in_coming_soon)
    val youtubePlaylistCreateUnavailable = stringResource(R.string.youtube_you_create_playlist_unavailable)
    val youtubeWebLoginSuccess = stringResource(R.string.youtube_web_login_success)

    val authSession by authViewModel.session.collectAsStateWithLifecycle()
    val isYoutubeAuthed = authSession is UserSession.Authenticated
    val loginHintEmail = (authSession as? UserSession.Authenticated)?.profile?.email

    androidx.compose.runtime.LaunchedEffect(pendingArtistChannel) {
        pendingArtistChannel?.let { channel ->
            selectedChannel = channel
            onPendingArtistConsumed()
        }
    }

    androidx.compose.runtime.LaunchedEffect(switchToLibraryTab) {
        if (switchToLibraryTab) {
            selectedTabName = MainTab.Library.name
            onSwitchToLibraryTabConsumed()
        }
    }

    val googleSignIn = rememberGoogleSignInLauncher(
        onError = { message ->
            scope.launch { snackbarHostState.showSnackbar(message) }
        },
        onSuccess = {
            YoutubeCookieJar.syncFromWebView()
            if (!YoutubeCookieJar.hasAuthCookies()) {
                showYoutubeWebLogin = true
            }
        },
    )

    val onSignInClick: () -> Unit = {
        if (googleSignIn.canSignIn) {
            googleSignIn.startSignIn()
        } else {
            val message = googleSignIn.notConfiguredMessage ?: signInComingSoon
            scope.launch { snackbarHostState.showSnackbar(message) }
        }
    }

    if (showYoutubeWebLogin) {
        YoutubeWebLoginScreen(
            loginHintEmail = loginHintEmail,
            onSuccess = {
                showYoutubeWebLogin = false
                youtubeCookieSessionEpoch += 1
                scope.launch { snackbarHostState.showSnackbar(youtubeWebLoginSuccess) }
            },
            onDismiss = { showYoutubeWebLogin = false },
            modifier = Modifier.fillMaxSize(),
        )
        return
    }

    authSession?.let { session ->
        AccountSwitcherSheet(
            session = session,
            visible = showAccountSwitcher,
            onDismiss = { showAccountSwitcher = false },
            onAddAccountClick = {
                showAccountSwitcher = false
                onSignInClick()
            },
            onSignOutClick = {
                showAccountSwitcher = false
                authViewModel.switchToGuestMode()
            },
        )
    }

    val imeVisible = WindowInsets.isImeVisible

    Scaffold(
        modifier = modifier.fillMaxSize(),
        snackbarHost = { SnackbarHost(snackbarHostState) },
        bottomBar = {
            // Hide chrome above the keyboard (Search focus / IME).
            if (!imeVisible) {
                Column {
                    if (globalPlaybackState.showMiniPlayer) {
                        MiniPlayerBar(
                            state = globalPlaybackState,
                            onOpenPlayer = {
                                globalPlaybackState.nowPlaying?.videoId?.let(onMiniPlayerOpenPlayer)
                            },
                            onTogglePlayPause = onMiniPlayerTogglePlayPause,
                            onSkipNext = onMiniPlayerSkipNext,
                        )
                    }
                    NavigationBar {
                        val navItemColors = NavigationBarItemDefaults.colors(
                            selectedIconColor = MaterialTheme.colorScheme.primary,
                            selectedTextColor = MaterialTheme.colorScheme.primary,
                            unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                            unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant,
                            indicatorColor = MaterialTheme.colorScheme.primaryContainer,
                        )
                        MainTab.entries.forEach { tab ->
                            val selected = selectedTab == tab
                            val labelRes = if (tab == MainTab.Subscriptions && isYoutubeAuthed) {
                                R.string.nav_youtube
                            } else {
                                tab.labelRes
                            }
                            NavigationBarItem(
                                selected = selected,
                                onClick = { selectedTabName = tab.name },
                                colors = navItemColors,
                                icon = {
                                    Icon(
                                        imageVector = if (selected) {
                                            tab.selectedIcon
                                        } else {
                                            tab.unselectedIcon
                                        },
                                        contentDescription = stringResource(labelRes),
                                    )
                                },
                                label = {
                                    Text(
                                        text = stringResource(labelRes),
                                        style = MaterialTheme.typography.labelSmall.copy(
                                            fontWeight = if (selected) {
                                                FontWeight.Bold
                                            } else {
                                                FontWeight.Normal
                                            },
                                        ),
                                        maxLines = 1,
                                        softWrap = false,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                },
                                alwaysShowLabel = true,
                            )
                        }
                    }
                }
            }
        },
    ) { innerPadding ->
        when {
            selectedYoutubePlaylist != null -> {
                val playlist = selectedYoutubePlaylist!!
                YoutubePlaylistItemsScreen(
                    playlistId = playlist.playlistId,
                    title = playlist.title,
                    onBack = { selectedYoutubePlaylist = null },
                    onVideoClick = onVideoClick,
                    onPlayPlaylist = onPlayPlaylist,
                    modifier = Modifier
                        .fillMaxSize()
                        .mainTabPadding(innerPadding, applyTopInset = false),
                )
            }
            selectedChannel != null -> {
                ChannelVideosScreen(
                    channel = selectedChannel!!,
                    onBack = { selectedChannel = null },
                    onVideoClick = onVideoClick,
                    onPlayPlaylist = onPlayPlaylist,
                    modifier = Modifier
                        .fillMaxSize()
                        .mainTabPadding(innerPadding, applyTopInset = false),
                )
            }
            showYoutubePlaylists -> {
                YoutubePlaylistsListScreen(
                    onBack = { showYoutubePlaylists = false },
                    onPlaylistClick = { playlist ->
                        showYoutubePlaylists = false
                        selectedYoutubePlaylist = playlist
                    },
                    modifier = Modifier
                        .fillMaxSize()
                        .mainTabPadding(innerPadding, applyTopInset = false),
                )
            }
            showSubscriptionChannels -> {
                SubscriptionChannelsScreen(
                    onBack = { showSubscriptionChannels = false },
                    onChannelClick = { channel -> selectedChannel = channel },
                    modifier = Modifier
                        .fillMaxSize()
                        .mainTabPadding(innerPadding, applyTopInset = false),
                )
            }
            else -> when (selectedTab) {
                MainTab.Home -> HomeScreen(
                    onVideoClick = onVideoClick,
                    onPlayPlaylist = onPlayPlaylist,
                    contentPadding = innerPadding,
                    modifier = Modifier.fillMaxSize(),
                )
                MainTab.Shorts -> ShortsScreen(
                    modifier = Modifier
                        .fillMaxSize()
                        .mainTabPadding(innerPadding, applyTopInset = true),
                )
                MainTab.Search -> SearchScreen(
                    onVideoClick = onVideoClick,
                    onChannelClick = { channel -> selectedChannel = channel },
                    onPlayPlaylist = onPlayPlaylist,
                    modifier = Modifier
                        .fillMaxSize()
                        .mainTabPadding(innerPadding, applyTopInset = true),
                )
                MainTab.Subscriptions -> SubscriptionsScreen(
                    session = authSession,
                    onSignInClick = onSignInClick,
                    onVideoClick = onVideoClick,
                    onChannelListClick = { showSubscriptionChannels = true },
                    onChannelClick = { channel -> selectedChannel = channel },
                    onSwitchAccountClick = { showAccountSwitcher = true },
                    onPlaylistsViewAll = { showYoutubePlaylists = true },
                    onPlaylistClick = { playlist -> selectedYoutubePlaylist = playlist },
                    onCreatePlaylistClick = {
                        scope.launch {
                            snackbarHostState.showSnackbar(youtubePlaylistCreateUnavailable)
                        }
                    },
                    onYoutubeWebLoginClick = { showYoutubeWebLogin = true },
                    youtubeCookieSessionEpoch = youtubeCookieSessionEpoch,
                    modifier = Modifier
                        .fillMaxSize()
                        .mainTabPadding(innerPadding, applyTopInset = true),
                )
                MainTab.Library -> LibraryScreen(
                    onVideoClick = onVideoClick,
                    onSignInClick = onSignInClick,
                    onSignOutClick = { authViewModel.switchToGuestMode() },
                    onNavigateHomeTab = { selectedTabName = MainTab.Home.name },
                    onPlayPlaylist = onPlayPlaylist,
                    onTogglePlayPause = onMiniPlayerTogglePlayPause,
                    onGoToArtist = { channel -> selectedChannel = channel },
                    pendingAlbumName = pendingAlbumName,
                    onPendingAlbumConsumed = onPendingAlbumConsumed,
                    modifier = Modifier
                        .fillMaxSize()
                        .mainTabPadding(innerPadding, applyTopInset = false),
                )
            }
        }
    }
}
