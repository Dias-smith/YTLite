package com.ytlite.player.ui.library

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlaylistPlay
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.ytlite.player.data.local.entity.PlaylistSystemType
import com.ytlite.player.data.model.LibraryItem

@Composable
fun LibraryPlaylistThumbnail(
    item: LibraryItem,
    modifier: Modifier = Modifier,
    iconSize: Dp = 28.dp,
) {
    when (item) {
        is LibraryItem.Playlist -> {
            if (!item.coverUrl.isNullOrBlank()) {
                LibraryImage(
                    model = item.coverUrl,
                    contentDescription = item.title,
                    modifier = modifier,
                )
            } else {
                SystemPlaylistIcon(
                    systemType = item.systemType,
                    modifier = modifier,
                    iconSize = iconSize,
                )
            }
        }
        else -> {
            LibraryImage(
                model = item.coverUrl,
                contentDescription = item.title,
                modifier = modifier
                    .clip(RoundedCornerShape(8.dp))
                    .background(MaterialTheme.colorScheme.surfaceVariant),
            )
        }
    }
}

@Composable
fun SystemPlaylistIcon(
    systemType: String?,
    modifier: Modifier = Modifier,
    iconSize: Dp = 28.dp,
) {
    val shape = RoundedCornerShape(8.dp)
    when (systemType) {
        PlaylistSystemType.FAVORITES -> {
            Box(
                modifier = modifier
                    .clip(shape)
                    .background(
                        Brush.linearGradient(
                            colors = listOf(Color(0xFF4FC3F7), Color(0xFFE91E63)),
                        ),
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Default.ThumbUp,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(iconSize),
                )
            }
        }
        PlaylistSystemType.WATCH_LATER -> {
            Box(
                modifier = modifier
                    .clip(shape)
                    .background(MaterialTheme.colorScheme.primaryContainer),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Default.Schedule,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onPrimaryContainer,
                    modifier = Modifier.size(iconSize),
                )
            }
        }
        else -> {
            Box(
                modifier = modifier
                    .clip(shape)
                    .background(MaterialTheme.colorScheme.surfaceVariant),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = playlistIcon(systemType),
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(iconSize),
                )
            }
        }
    }
}

private fun playlistIcon(systemType: String?): ImageVector = when (systemType) {
    PlaylistSystemType.WATCH_LATER -> Icons.Default.Schedule
    PlaylistSystemType.FAVORITES -> Icons.Default.ThumbUp
    else -> Icons.Default.PlaylistPlay
}
