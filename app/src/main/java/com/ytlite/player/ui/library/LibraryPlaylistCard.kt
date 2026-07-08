package com.ytlite.player.ui.library

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlaylistPlay
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.ytlite.player.R
import com.ytlite.player.data.local.entity.PlaylistEntity
import com.ytlite.player.data.local.entity.PlaylistSystemType
import com.ytlite.player.data.model.DataSource

@Composable
fun LibraryPlaylistsRow(
    playlists: List<PlaylistEntity>,
    onPlaylistClick: (PlaylistEntity) -> Unit,
    onCloneYoutubePlaylist: (PlaylistEntity) -> Unit,
    modifier: Modifier = Modifier,
    emptyText: String? = null,
) {
    if (playlists.isEmpty()) {
        Text(
            text = emptyText ?: stringResource(R.string.library_playlists_empty),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
        )
        return
    }

    LazyRow(
        modifier = modifier.fillMaxWidth(),
        contentPadding = PaddingValues(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        items(
            items = playlists,
            key = { it.playlistId },
        ) { playlist ->
            UnifiedPlaylistCard(
                playlist = playlist,
                onClick = { onPlaylistClick(playlist) },
                onCloneClick = { onCloneYoutubePlaylist(playlist) },
            )
        }
    }
}

@Composable
private fun UnifiedPlaylistCard(
    playlist: PlaylistEntity,
    onClick: () -> Unit,
    onCloneClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val isYoutube = playlist.dataSource == DataSource.YOUTUBE
    val icon = playlistIcon(playlist)
    val subtitle = when {
        isYoutube -> stringResource(R.string.library_youtube_playlist)
        playlist.systemType != null -> stringResource(R.string.library_private_playlist)
        else -> stringResource(R.string.library_local_playlist)
    }

    Column(modifier = modifier.width(160.dp)) {
        Box(
            modifier = Modifier
                .width(160.dp)
                .height(90.dp),
        ) {
            if (!playlist.coverUrlOrPath.isNullOrBlank()) {
                AsyncImage(
                    model = playlist.coverUrlOrPath,
                    contentDescription = playlist.name,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .width(160.dp)
                        .height(90.dp)
                        .offset(y = 8.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .clickable(onClick = onClick),
                )
            } else {
                StackedPlaylistPlaceholder(
                    icon = icon,
                    onClick = onClick,
                )
            }
            if (isYoutube) {
                YoutubeSourceBadge(
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .offset(y = 4.dp),
                )
            }
        }
        Text(
            text = displayName(playlist),
            style = MaterialTheme.typography.bodyMedium,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 12.dp),
        )
        Text(
            text = subtitle,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        if (isYoutube) {
            TextButton(
                onClick = onCloneClick,
                modifier = Modifier.padding(top = 2.dp),
                contentPadding = PaddingValues(0.dp),
            ) {
                Text(
                    text = stringResource(R.string.library_clone_to_local),
                    style = MaterialTheme.typography.labelMedium,
                )
            }
        }
    }
}

@Composable
fun YoutubeSourceBadge(modifier: Modifier = Modifier) {
    Text(
        text = stringResource(R.string.library_youtube_badge),
        color = Color.White,
        style = MaterialTheme.typography.labelSmall,
        modifier = modifier
            .background(Color(0xFFFF0000), RoundedCornerShape(4.dp))
            .padding(horizontal = 6.dp, vertical = 2.dp),
    )
}

@Composable
private fun StackedPlaylistPlaceholder(
    icon: ImageVector,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(modifier = modifier.width(160.dp).height(90.dp)) {
        Box(
            modifier = Modifier
                .width(150.dp)
                .height(82.dp)
                .offset(x = 8.dp, y = 0.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(Color(0xFF3A3A3A)),
        )
        Box(
            modifier = Modifier
                .width(155.dp)
                .height(86.dp)
                .offset(x = 4.dp, y = 4.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(Color(0xFF4A4A4A)),
        )
        Box(
            modifier = Modifier
                .width(160.dp)
                .height(90.dp)
                .offset(y = 8.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(Color(0xFF5A5A5A))
                .clickable(onClick = onClick),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.width(36.dp),
            )
        }
    }
}

@Composable
private fun displayName(playlist: PlaylistEntity): String = when (playlist.systemType) {
    PlaylistSystemType.WATCH_LATER -> stringResource(R.string.library_watch_later)
    PlaylistSystemType.FAVORITES -> stringResource(R.string.library_liked_videos)
    else -> playlist.name
}

@Composable
private fun playlistIcon(playlist: PlaylistEntity): ImageVector = when (playlist.systemType) {
    PlaylistSystemType.WATCH_LATER -> Icons.Filled.Schedule
    PlaylistSystemType.FAVORITES -> Icons.Filled.ThumbUp
    else -> Icons.Filled.PlaylistPlay
}
