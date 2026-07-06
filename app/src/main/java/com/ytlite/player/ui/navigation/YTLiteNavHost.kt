package com.ytlite.player.ui.navigation

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.ytlite.player.ui.main.MainScreen
import com.ytlite.player.ui.player.PlayerScreen
import com.ytlite.player.ui.player.PlayerViewModel

object Routes {
    const val MAIN = "main"
    const val PLAYER = "player/{videoId}"

    fun player(videoId: String): String = "player/$videoId"
}

@Composable
fun YTLiteNavHost(modifier: Modifier = Modifier) {
    val navController = rememberNavController()

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
            PlayerScreen(
                onBack = { navController.popBackStack() },
                viewModel = playerViewModel,
            )
        }
    }
}
