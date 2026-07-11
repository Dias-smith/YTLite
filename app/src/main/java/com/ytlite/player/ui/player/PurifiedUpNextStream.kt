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
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.ytlite.player.R
import com.ytlite.player.ui.trackaction.TrackActionSource
import com.ytlite.player.data.model.VideoItem
import com.ytlite.player.ui.trackaction.LocalTrackMoreClick
import com.ytlite.player.ui.trackaction.TrackActionContext

@Composable
fun PurifiedUpNextItem(
    item: VideoItem,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val onTrackMoreClick = LocalTrackMoreClick.current
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AsyncImage(
            model = ImageRequest.Builder(context)
                .data(item.thumbnailUrl)
                .allowRgb565(true)
                .crossfade(false)
                .build(),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .size(width = 120.dp, height = 68.dp)
                .clip(RoundedCornerShape(8.dp)),
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = item.title,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = item.channelName,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        IconButton(onClick = {
            onTrackMoreClick(
                TrackActionContext.fromVideoItem(item, TrackActionSource.PLAYER_UP_NEXT),
            )
        }) {
            Icon(Icons.Default.MoreVert, contentDescription = stringResource(R.string.library_song_more))
        }
    }
}

@Composable
fun PurifiedUpNextHeader(
    modifier: Modifier = Modifier,
) {
    Text(
        text = stringResource(R.string.player_up_next),
        style = MaterialTheme.typography.titleSmall,
        modifier = modifier.padding(horizontal = 16.dp, vertical = 8.dp),
    )
}
