package com.ytlite.player.ui.navigation

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import android.app.Application
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.ytlite.player.data.model.SubscriptionChannel
import com.ytlite.player.data.model.VideoItem
import com.ytlite.player.ui.main.MainScreen
import com.ytlite.player.ui.player.PlayerScreen
import com.ytlite.player.ui.player.PlayerLaunchPreview
import com.ytlite.player.ui.player.videoPreview
import com.ytlite.player.ui.player.PlayerViewModel
import com.ytlite.player.playback.GlobalPlaybackViewModel
import com.ytlite.player.playback.PlaybackNavigation
import com.ytlite.player.playback.PlaybackPrefetcher
import com.ytlite.player.ui.auth.AuthViewModel
import com.ytlite.player.ui.subscriptions.ChannelVideosScreen
import com.ytlite.player.ui.playlistaction.PlaylistActionHost
import com.ytlite.player.ui.trackaction.TrackActionHost
import com.ytlite.player.ui.trackaction.TrackActionNavigation

object Routes {
    const val MAIN = "main"
    const val PLAYER = "player/{videoId}"

    fun player(videoId: String): String = "player/$videoId"
}

@Composable
fun YTLiteNavHost(modifier: Modifier = Modifier) {
    val navController = rememberNavController()
    val application = LocalContext.current.applicationContext as Application
    val globalPlaybackViewModel: GlobalPlaybackViewModel = viewModel(
        factory = GlobalPlaybackViewModel.factory(application),
    )
    val authViewModel: AuthViewModel = viewModel(factory = AuthViewModel.factory(application))
    val globalPlaybackState by globalPlaybackViewModel.uiState.collectAsStateWithLifecycle()

    var pendingArtistChannel by remember { mutableStateOf<SubscriptionChannel?>(null) }
    var pendingAlbumName by remember { mutableStateOf<String?>(null) }
    var switchToLibraryTab by remember { mutableStateOf(false) }
    var playerChannelOverlay by remember { mutableStateOf<SubscriptionChannel?>(null) }

    LaunchedEffect(navController) {
        PlaybackNavigation.openPlayerRequests.collect { videoId ->
            val route = Routes.player(videoId)
            val currentRoute = navController.currentBackStackEntry?.destination?.route
            if (currentRoute != route) {
                PlaybackPrefetcher.prefetch(videoId)
                navController.navigate(route) {
                    launchSingleTop = true
                }
            }
        }
    }

    fun openPlayer(video: VideoItem, launchSingleTop: Boolean = false) {
        PlayerLaunchPreview.set(video)
        PlaybackPrefetcher.prefetch(video.videoId)
        val route = Routes.player(video.videoId)
        navController.navigate(route) {
            if (launchSingleTop) {
                this.launchSingleTop = true
            }
        }
    }

    TrackActionHost(
        navigation = TrackActionNavigation(
            onGoToArtist = { channel -> pendingArtistChannel = channel },
            onGoToAlbum = { album ->
                pendingAlbumName = album
                switchToLibraryTab = true
            },
        ),
        onRemoveFromQueue = globalPlaybackViewModel::removeFromQueue,
    ) {
        PlaylistActionHost(
            onShufflePlay = { items, sourcePlaylistId ->
                globalPlaybackViewModel.shufflePlayPlaylist(items, sourcePlaylistId)
            },
        ) {
        Box(modifier = modifier.fillMaxSize()) {
            NavHost(
                navController = navController,
                startDestination = Routes.MAIN,
                modifier = Modifier.fillMaxSize(),
            ) {
                composable(Routes.MAIN) {
                    MainScreen(
                        onVideoClick = { video -> openPlayer(video) },
                        globalPlaybackState = globalPlaybackState,
                        onMiniPlayerOpenPlayer = { videoId ->
                            openPlayer(video = videoPreview(videoId), launchSingleTop = true)
                        },
                        onMiniPlayerTogglePlayPause = globalPlaybackViewModel::togglePlayPause,
                        onMiniPlayerSkipNext = globalPlaybackViewModel::skipToNext,
                        onPlayPlaylist = { items, startIndex, sourcePlaylistId ->
                            globalPlaybackViewModel.playPlaylist(
                                items = items,
                                startIndex = startIndex,
                                sourcePlaylistId = sourcePlaylistId,
                            )
                        },
                        authViewModel = authViewModel,
                        pendingArtistChannel = pendingArtistChannel,
                        onPendingArtistConsumed = { pendingArtistChannel = null },
                        pendingAlbumName = pendingAlbumName,
                        onPendingAlbumConsumed = { pendingAlbumName = null },
                        switchToLibraryTab = switchToLibraryTab,
                        onSwitchToLibraryTabConsumed = { switchToLibraryTab = false },
                    )
                }
                composable(
                    route = Routes.PLAYER,
                    arguments = listOf(
                        navArgument("videoId") { type = NavType.StringType },
                    ),
                ) { backStackEntry ->
                    val videoId = backStackEntry.arguments?.getString("videoId")
                    if (videoId == null) {
                        navController.popBackStack()
                        return@composable
                    }
                    val playerViewModel: PlayerViewModel = viewModel(
                        viewModelStoreOwner = backStackEntry,
                        factory = PlayerViewModel.factory(videoId, application),
                    )
                    LaunchedEffect(Unit) {
                        globalPlaybackViewModel.onEnterPlayerScreen()
                    }
                    PlayerScreen(
                        onBack = {
                            globalPlaybackViewModel.onLeavePlayerScreen()
                            val currentRoute = navController.currentBackStackEntry?.destination?.route
                            if (currentRoute?.startsWith("player/") == true) {
                                navController.popBackStack()
                            }
                        },
                        onChannelClick = { channel -> playerChannelOverlay = channel },
                        viewModel = playerViewModel,
                        globalPlaybackViewModel = globalPlaybackViewModel,
                        globalPlaybackState = globalPlaybackState,
                    )
                }
            }

            playerChannelOverlay?.let { channel ->
                ChannelVideosScreen(
                    channel = channel,
                    onBack = { playerChannelOverlay = null },
                    onVideoClick = { video ->
                        playerChannelOverlay = null
                        openPlayer(video, launchSingleTop = true)
                    },
                    modifier = Modifier.fillMaxSize(),
                )
            }
        }
        }
    }
}
