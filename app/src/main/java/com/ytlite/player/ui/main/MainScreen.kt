package com.ytlite.player.ui.main

import androidx.compose.foundation.layout.Box
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
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import com.ytlite.player.R
import com.ytlite.player.ui.home.HomeScreen

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
    modifier: Modifier = Modifier,
) {
    var selectedTab by rememberSaveable { mutableIntStateOf(MainTab.Home.ordinal) }

    Scaffold(
        modifier = modifier.fillMaxSize(),
        bottomBar = {
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
        },
    ) { innerPadding ->
        when (MainTab.entries[selectedTab]) {
            MainTab.Home -> HomeScreen(
                onVideoClick = onVideoClick,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding),
            )
            else -> PlaceholderTab(
                label = stringResource(MainTab.entries[selectedTab].labelRes),
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding),
            )
        }
    }
}

@Composable
private fun PlaceholderTab(
    label: String,
    modifier: Modifier = Modifier,
) {
    Box(modifier = modifier, contentAlignment = Alignment.Center) {
        Text(
            text = "$label · ${stringResource(R.string.placeholder_coming_soon)}",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
