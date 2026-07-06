package com.ytlite.player

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import com.ytlite.player.ui.navigation.YTLiteNavHost
import com.ytlite.player.ui.theme.YTLiteTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            YTLiteTheme {
                YTLiteNavHost(modifier = Modifier.fillMaxSize())
            }
        }
    }
}
