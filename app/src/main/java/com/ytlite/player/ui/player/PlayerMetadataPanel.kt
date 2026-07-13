package com.ytlite.player.ui.player

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.ytlite.player.R
import com.ytlite.player.data.model.VideoPlayback

@Composable
fun PlayerMetadataPanel(
    playback: VideoPlayback,
    isLiked: Boolean,
    isDisliked: Boolean,
    onLike: () -> Unit,
    onDislike: () -> Unit,
    onShare: () -> Unit,
    onSaveToPlaylist: () -> Unit,
    onChannelClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            text = playback.title,
            style = MaterialTheme.typography.titleLarge,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )

        if (playback.viewCount > 0L) {
            Text(
                text = stringResource(
                    R.string.player_view_count,
                    formatPlayerViewCount(playback.viewCount),
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClick = onChannelClick),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(
                imageVector = Icons.Filled.AccountCircle,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape),
            )
            Text(
                text = playback.channelName,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            Button(
                onClick = { },
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.onSurface,
                    contentColor = MaterialTheme.colorScheme.surface,
                ),
            ) {
                Text(text = stringResource(R.string.player_subscribe))
            }
        }

        PlayerActionBar(
            isLiked = isLiked,
            isDisliked = isDisliked,
            onLike = onLike,
            onDislike = onDislike,
            onShare = onShare,
            onSaveToPlaylist = onSaveToPlaylist,
        )
    }
}

@Composable
fun PlayerShareAction(videoId: String) {
    val context = androidx.compose.ui.platform.LocalContext.current
    shareVideo(context, videoId)
}

fun shareVideo(context: android.content.Context, videoId: String) {
    val intent = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(android.content.Intent.EXTRA_TEXT, "https://www.youtube.com/watch?v=$videoId")
    }
    context.startActivity(android.content.Intent.createChooser(intent, null))
}
