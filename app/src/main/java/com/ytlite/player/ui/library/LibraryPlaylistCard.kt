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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.ytlite.player.R

@Composable
fun LibraryPlaylistsRow(
    watchLaterCount: Int,
    likedCount: Int,
    onPlaylistClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyRow(
        modifier = modifier.fillMaxWidth(),
        contentPadding = PaddingValues(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item(key = "watch_later") {
            LibraryPlaylistCard(
                title = stringResource(R.string.library_watch_later),
                subtitle = stringResource(R.string.library_private_playlist),
                icon = Icons.Filled.Schedule,
                onClick = onPlaylistClick,
            )
        }
        item(key = "liked") {
            LibraryPlaylistCard(
                title = stringResource(R.string.library_liked_videos),
                subtitle = stringResource(R.string.library_private_playlist),
                icon = Icons.Filled.ThumbUp,
                onClick = onPlaylistClick,
            )
        }
    }
}

@Composable
private fun LibraryPlaylistCard(
    title: String,
    subtitle: String,
    icon: ImageVector,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.width(160.dp)) {
        Box(
            modifier = Modifier
                .width(160.dp)
                .height(90.dp),
        ) {
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
        Text(
            text = title,
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.padding(top = 12.dp),
        )
        Text(
            text = subtitle,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
