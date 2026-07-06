package com.ytlite.player.ui.shorts

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.ytlite.player.ui.web.EmbeddedWebView

object ShortsConfig {
    const val URL = "https://www.youtube.com/shorts/"
}

@Composable
fun ShortsScreen(
    modifier: Modifier = Modifier,
) {
    EmbeddedWebView(
        url = ShortsConfig.URL,
        modifier = modifier.fillMaxSize(),
    )
}
