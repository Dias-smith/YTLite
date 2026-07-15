package com.ytlite.player.ui.player

import androidx.compose.foundation.basicMarquee
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
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.ytlite.player.R
import com.ytlite.player.data.model.VideoPlayback
import com.ytlite.player.playback.NowPlaying
import com.ytlite.player.ui.trackaction.LocalTrackDownloadClick
import com.ytlite.player.ui.trackaction.LocalTrackMoreClick
import com.ytlite.player.ui.trackaction.TrackActionContext
import com.ytlite.player.ui.trackaction.TrackActionSource

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
    isSubscribed: Boolean = false,
    subscribeEnabled: Boolean = false,
    onSubscribeClick: () -> Unit = {},
    modifier: Modifier = Modifier,
    showTitle: Boolean = true,
) {
    val onTrackMoreClick = LocalTrackMoreClick.current
    val onTrackDownloadClick = LocalTrackDownloadClick.current
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (showTitle) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    text = playback.title,
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    softWrap = false,
                    overflow = TextOverflow.Visible,
                    modifier = Modifier
                        .weight(1f)
                        .basicMarquee(
                            iterations = Int.MAX_VALUE,
                            velocity = 30.dp,
                        ),
                )
                IconButton(
                    onClick = {
                        onTrackMoreClick(
                            TrackActionContext.fromVideoItem(
                                videoPreview(
                                    videoId = playback.videoId,
                                    title = playback.title,
                                    channelName = playback.channelName,
                                    channelId = playback.channelId.takeIf { it.isNotBlank() },
                                    thumbnailUrl = NowPlaying.thumbnailUrlFor(playback.videoId),
                                ),
                                TrackActionSource.PLAYER_UP_NEXT,
                            ),
                        )
                    },
                    modifier = Modifier.size(40.dp),
                ) {
                    Icon(
                        imageVector = Icons.Default.MoreVert,
                        contentDescription = stringResource(R.string.library_song_more),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                text = playback.channelName,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier
                    .weight(1f, fill = false)
                    .clickable(onClick = onChannelClick),
            )
            Surface(
                onClick = onSubscribeClick,
                enabled = subscribeEnabled,
                shape = RoundedCornerShape(50),
                color = if (isSubscribed) {
                    MaterialTheme.colorScheme.surfaceVariant
                } else {
                    MaterialTheme.colorScheme.onSurface
                },
                contentColor = if (isSubscribed) {
                    MaterialTheme.colorScheme.onSurfaceVariant
                } else {
                    MaterialTheme.colorScheme.surface
                },
            ) {
                Text(
                    text = stringResource(
                        if (isSubscribed) R.string.player_subscribed else R.string.player_subscribe,
                    ),
                    style = MaterialTheme.typography.labelMedium,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                )
            }
        }

        PlayerActionBar(
            isLiked = isLiked,
            isDisliked = isDisliked,
            onLike = onLike,
            onDislike = onDislike,
            onShare = onShare,
            onSaveToPlaylist = onSaveToPlaylist,
            onDownload = { onTrackDownloadClick(playback.videoId) },
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
