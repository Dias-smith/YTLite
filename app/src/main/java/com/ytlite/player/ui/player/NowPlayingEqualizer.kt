package com.ytlite.player.ui.player

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.ytlite.player.R

@Composable
fun NowPlayingEqualizer(
    isAnimating: Boolean,
    modifier: Modifier = Modifier,
    color: Color = MaterialTheme.colorScheme.primary,
) {
    val barModifier = Modifier
        .width(3.dp)
        .fillMaxHeight()
        .background(color, RoundedCornerShape(1.dp))

    val contentDesc = stringResource(R.string.player_now_playing)
    Row(
        modifier = modifier
            .height(14.dp)
            .width(16.dp)
            .semantics { contentDescription = contentDesc },
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        if (isAnimating) {
            val transition = rememberInfiniteTransition(label = "nowPlayingEqualizer")
            val barOne by transition.animateFloat(
                initialValue = 0.35f,
                targetValue = 1f,
                animationSpec = infiniteRepeatable(
                    animation = tween(durationMillis = 420, easing = LinearEasing),
                    repeatMode = RepeatMode.Reverse,
                ),
                label = "barOne",
            )
            val barTwo by transition.animateFloat(
                initialValue = 0.55f,
                targetValue = 0.95f,
                animationSpec = infiniteRepeatable(
                    animation = tween(durationMillis = 360, easing = LinearEasing),
                    repeatMode = RepeatMode.Reverse,
                ),
                label = "barTwo",
            )
            val barThree by transition.animateFloat(
                initialValue = 0.25f,
                targetValue = 1f,
                animationSpec = infiniteRepeatable(
                    animation = tween(durationMillis = 480, easing = LinearEasing),
                    repeatMode = RepeatMode.Reverse,
                ),
                label = "barThree",
            )
            EqualizerBar(barModifier, barOne)
            EqualizerBar(barModifier, barTwo)
            EqualizerBar(barModifier, barThree)
        } else {
            EqualizerBar(barModifier, 0.35f)
            EqualizerBar(barModifier, 0.55f)
            EqualizerBar(barModifier, 0.4f)
        }
    }
}

@Composable
private fun EqualizerBar(
    modifier: Modifier,
    heightFraction: Float,
) {
    Box(
        modifier = Modifier
            .fillMaxHeight()
            .width(3.dp),
        contentAlignment = Alignment.BottomCenter,
    ) {
        Box(
            modifier = modifier
                .fillMaxHeight(heightFraction.coerceIn(0.2f, 1f)),
        )
    }
}
