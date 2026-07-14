package com.ytlite.player.ui.player

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.QueueMusic
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.outlined.RepeatOne
import androidx.compose.material.icons.outlined.Shuffle
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.ytlite.player.R
import com.ytlite.player.playback.UpNextPlaybackMode
import com.ytlite.player.ui.image.thumbnailRequest
import com.ytlite.player.ui.trackaction.TrackActionSource
import com.ytlite.player.data.model.VideoItem
import com.ytlite.player.ui.trackaction.LocalTrackMoreClick
import com.ytlite.player.ui.trackaction.TrackActionContext

@Composable
fun PurifiedUpNextItem(
    item: VideoItem,
    isCurrentlyPlaying: Boolean,
    isPlaying: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val onTrackMoreClick = LocalTrackMoreClick.current
    val subtitle = listOfNotNull(
        item.channelName.takeIf { it.isNotBlank() },
        item.viewCountText?.takeIf { it.isNotBlank() },
    ).joinToString(separator = " · ")

    Row(
        modifier = modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier.size(width = 120.dp, height = 68.dp),
        ) {
            AsyncImage(
                model = thumbnailRequest(context, item.thumbnailUrl),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .fillMaxWidth()
                    .size(width = 120.dp, height = 68.dp)
                    .clip(RoundedCornerShape(8.dp)),
            )
            if (!item.durationText.isNullOrBlank()) {
                Text(
                    text = item.durationText,
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.White,
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(4.dp)
                        .background(
                            color = Color.Black.copy(alpha = 0.8f),
                            shape = RoundedCornerShape(4.dp),
                        )
                        .padding(horizontal = 4.dp, vertical = 2.dp),
                )
            }
        }
        Column(modifier = Modifier.weight(1f)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                if (isCurrentlyPlaying) {
                    NowPlayingEqualizer(
                        isAnimating = isPlaying,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
                Text(
                    text = item.title,
                    style = MaterialTheme.typography.bodyMedium,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false),
                )
            }
            if (subtitle.isNotBlank()) {
                Text(
                    text = subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
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
    currentMode: UpNextPlaybackMode,
    onModeSelected: (UpNextPlaybackMode) -> Unit,
    selectedTab: PlayerListTab,
    onTabSelected: (PlayerListTab) -> Unit,
    showRecommendTab: Boolean,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(start = 16.dp, end = 8.dp, top = 4.dp, bottom = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (showRecommendTab) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                UpNextListTab(
                    label = stringResource(R.string.player_up_next),
                    selected = selectedTab == PlayerListTab.UpNext,
                    onClick = { onTabSelected(PlayerListTab.UpNext) },
                )
                UpNextListTab(
                    label = stringResource(R.string.player_recommend),
                    selected = selectedTab == PlayerListTab.Recommend,
                    onClick = { onTabSelected(PlayerListTab.Recommend) },
                )
            }
        } else {
            Text(
                text = stringResource(R.string.player_up_next),
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(vertical = 8.dp),
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(0.dp)) {
            UpNextPlaybackModeButton(
                selected = currentMode == UpNextPlaybackMode.REPEAT_ONE,
                onClick = { onModeSelected(UpNextPlaybackMode.REPEAT_ONE) },
            ) {
                Icon(
                    imageVector = Icons.Outlined.RepeatOne,
                    contentDescription = stringResource(R.string.player_mode_repeat_one),
                )
            }
            UpNextPlaybackModeButton(
                selected = currentMode == UpNextPlaybackMode.SEQUENTIAL,
                onClick = { onModeSelected(UpNextPlaybackMode.SEQUENTIAL) },
            ) {
                Icon(
                    imageVector = Icons.AutoMirrored.Outlined.QueueMusic,
                    contentDescription = stringResource(R.string.player_mode_sequential),
                )
            }
            UpNextPlaybackModeButton(
                selected = currentMode == UpNextPlaybackMode.SHUFFLE,
                onClick = { onModeSelected(UpNextPlaybackMode.SHUFFLE) },
            ) {
                Icon(
                    imageVector = Icons.Outlined.Shuffle,
                    contentDescription = stringResource(R.string.player_mode_shuffle),
                )
            }
        }
    }
}

@Composable
private fun UpNextListTab(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val color = if (selected) {
        MaterialTheme.colorScheme.primary
    } else {
        MaterialTheme.colorScheme.onSurfaceVariant
    }
    Column(
        modifier = modifier
            .clickable(role = Role.Tab, onClick = onClick)
            .padding(vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
            color = color,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Box(
            modifier = Modifier
                .padding(top = 4.dp)
                .width(28.dp)
                .height(2.dp)
                .clip(RoundedCornerShape(1.dp))
                .background(if (selected) color else Color.Transparent),
        )
    }
}

@Composable
private fun UpNextPlaybackModeButton(
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    IconButton(
        onClick = onClick,
        modifier = modifier.size(40.dp),
    ) {
        CompositionLocalProvider(
            LocalContentColor provides if (selected) {
                MaterialTheme.colorScheme.primary
            } else {
                MaterialTheme.colorScheme.onSurfaceVariant
            },
        ) {
            content()
        }
    }
}
