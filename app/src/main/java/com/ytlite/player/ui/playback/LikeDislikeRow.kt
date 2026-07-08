package com.ytlite.player.ui.playback

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ThumbDown
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.ytlite.player.R

@Composable
fun LikeDislikeRow(
    isLiked: Boolean,
    isDisliked: Boolean,
    onLike: () -> Unit,
    onDislike: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = onLike) {
            Icon(
                imageVector = Icons.Filled.ThumbUp,
                contentDescription = stringResource(R.string.player_like),
                tint = if (isLiked) MaterialTheme.colorScheme.primary else Color(0xFF888888),
            )
        }
        IconButton(onClick = onDislike) {
            Icon(
                imageVector = Icons.Filled.ThumbDown,
                contentDescription = stringResource(R.string.player_dislike),
                tint = if (isDisliked) MaterialTheme.colorScheme.primary else Color(0xFF888888),
            )
        }
        Text(
            text = stringResource(R.string.player_like_dislike_hint),
            style = MaterialTheme.typography.bodySmall,
            color = Color(0xFF666666),
        )
    }
}
