package com.ytlite.player.ui.player

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.PlaylistAdd
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.ThumbDown
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.DownloadDone
import androidx.compose.material.icons.outlined.ThumbDown
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.ytlite.player.R

@Composable
fun PlayerActionBar(
    isLiked: Boolean,
    isDisliked: Boolean,
    onLike: () -> Unit,
    onDislike: () -> Unit,
    onShare: () -> Unit,
    onSaveToPlaylist: () -> Unit,
    onDownload: () -> Unit,
    isDownloaded: Boolean = false,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(28.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.55f),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 4.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            PlayerActionItem(
                icon = if (isLiked) Icons.Filled.ThumbUp else Icons.Outlined.ThumbUp,
                label = stringResource(R.string.player_like),
                selected = isLiked,
                onClick = onLike,
            )
            PlayerActionItem(
                icon = if (isDisliked) Icons.Filled.ThumbDown else Icons.Outlined.ThumbDown,
                label = stringResource(R.string.player_dislike),
                selected = isDisliked,
                onClick = onDislike,
            )
            PlayerActionItem(
                icon = Icons.Filled.Share,
                label = stringResource(R.string.player_share),
                selected = false,
                onClick = onShare,
            )
            PlayerActionItem(
                icon = Icons.AutoMirrored.Outlined.PlaylistAdd,
                label = stringResource(R.string.player_save_playlist),
                selected = false,
                onClick = onSaveToPlaylist,
            )
            PlayerActionItem(
                icon = if (isDownloaded) {
                    Icons.Outlined.DownloadDone
                } else {
                    Icons.Outlined.Download
                },
                label = stringResource(
                    if (isDownloaded) {
                        R.string.player_downloaded
                    } else {
                        R.string.player_download
                    },
                ),
                selected = isDownloaded,
                onClick = onDownload,
            )
        }
    }
}

@Composable
private fun PlayerActionItem(
    icon: ImageVector,
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val tint = if (selected) {
        MaterialTheme.colorScheme.primary
    } else {
        MaterialTheme.colorScheme.onSurface
    }
    Column(
        modifier = modifier
            .clickable(onClick = onClick)
            .padding(horizontal = 6.dp, vertical = 2.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = label,
            tint = tint,
            modifier = Modifier.size(22.dp),
        )
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = if (selected) {
                MaterialTheme.colorScheme.primary
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant
            },
            maxLines = 1,
        )
    }
}
