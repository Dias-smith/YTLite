package com.ytlite.player.ui.player

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.ThumbDown
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.outlined.PlaylistAdd
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.ytlite.player.R
import com.ytlite.player.data.model.VideoPlayback
import java.text.NumberFormat
import java.util.Locale

@Composable
fun PlayerMetadataPanel(
    playback: VideoPlayback,
    isDescriptionExpanded: Boolean,
    onToggleDescription: () -> Unit,
    onShare: () -> Unit,
    onSaveToPlaylist: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            text = playback.title,
            style = MaterialTheme.typography.titleLarge,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            AsyncImage(
                model = "https://i.ytimg.com/vi/${playback.videoId}/hqdefault.jpg",
                contentDescription = null,
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape),
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = playback.channelName,
                    style = MaterialTheme.typography.bodyMedium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (playback.viewCount > 0L) {
                    val formatted = NumberFormat.getNumberInstance(Locale.getDefault()).format(playback.viewCount)
                    Text(
                        text = stringResource(R.string.player_view_count, formatted),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
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

        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            contentPadding = PaddingValues(vertical = 4.dp),
        ) {
            item {
                OutlinedButton(onClick = { }) {
                    Icon(Icons.Filled.ThumbUp, contentDescription = null, modifier = Modifier.size(18.dp))
                    Text(stringResource(R.string.player_like), modifier = Modifier.padding(start = 6.dp))
                }
            }
            item {
                OutlinedButton(onClick = { }) {
                    Icon(Icons.Filled.ThumbDown, contentDescription = null, modifier = Modifier.size(18.dp))
                    Text(stringResource(R.string.player_dislike), modifier = Modifier.padding(start = 6.dp))
                }
            }
            item {
                OutlinedButton(onClick = onShare) {
                    Icon(Icons.Filled.Share, contentDescription = null, modifier = Modifier.size(18.dp))
                    Text(stringResource(R.string.player_share), modifier = Modifier.padding(start = 6.dp))
                }
            }
            item {
                OutlinedButton(onClick = onSaveToPlaylist) {
                    Icon(Icons.Outlined.PlaylistAdd, contentDescription = null, modifier = Modifier.size(18.dp))
                    Text(stringResource(R.string.player_save_playlist), modifier = Modifier.padding(start = 6.dp))
                }
            }
            item {
                OutlinedButton(onClick = { }) {
                    Icon(Icons.Filled.Download, contentDescription = null, modifier = Modifier.size(18.dp))
                    Text(stringResource(R.string.player_download), modifier = Modifier.padding(start = 6.dp))
                }
            }
        }

        if (playback.description.isNotBlank()) {
            Text(
                text = playback.description,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = if (isDescriptionExpanded) Int.MAX_VALUE else 3,
                overflow = TextOverflow.Ellipsis,
            )
            TextButton(onClick = onToggleDescription) {
                Text(
                    text = if (isDescriptionExpanded) {
                        stringResource(R.string.player_show_less)
                    } else {
                        stringResource(R.string.player_show_more)
                    },
                )
            }
        }
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
