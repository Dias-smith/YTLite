package com.ytlite.player.ui.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
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
import com.ytlite.player.ui.main.MainScreen
import com.ytlite.player.ui.player.PlayerScreen
import com.ytlite.player.ui.player.PlayerViewModel
import com.ytlite.player.playback.GlobalPlaybackViewModel
import com.ytlite.player.playback.PlaybackNavigation
import com.ytlite.player.ui.auth.AuthViewModel

object Routes {
    const val MAIN = "main"
    const val PLAYER = "player/{videoId}"

    fun player(videoId: String): String = "player/$videoId"
}

@Composable
fun YTLiteNavHost(modifier: Modifier = Modifier) {
    val navController = rememberNavController()
    val application = LocalContext.current.applicationContext as Application
    val globalPlaybackViewModel: GlobalPlaybackViewModel = viewModel()
    val authViewModel: AuthViewModel = viewModel(factory = AuthViewModel.factory(application))
    val globalPlaybackState by globalPlaybackViewModel.uiState.collectAsStateWithLifecycle()

    LaunchedEffect(navController) {
        PlaybackNavigation.openPlayerRequests.collect { videoId ->
            val route = Routes.player(videoId)
            val currentRoute = navController.currentBackStackEntry?.destination?.route
            if (currentRoute != route) {
                navController.navigate(route) {
                    launchSingleTop = true
                }
            }
        }
    }

    NavHost(
        navController = navController,
        startDestination = Routes.MAIN,
        modifier = modifier,
    ) {
        composable(Routes.MAIN) {
            MainScreen(
                onVideoClick = { videoId ->
                    navController.navigate(Routes.player(videoId))
                },
                globalPlaybackState = globalPlaybackState,
                onMiniPlayerOpen = {
                    val videoId = globalPlaybackState.nowPlaying?.videoId ?: return@MainScreen
                    navController.navigate(Routes.player(videoId))
                },
                onMiniPlayerTogglePlayPause = globalPlaybackViewModel::togglePlayPause,
                authViewModel = authViewModel,
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
            val application = LocalContext.current.applicationContext as android.app.Application
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
                    navController.popBackStack()
                },
                viewModel = playerViewModel,
            )
        }
    }
}
