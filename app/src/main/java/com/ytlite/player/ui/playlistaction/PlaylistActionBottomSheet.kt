package com.ytlite.player.ui.playlistaction

import android.app.Application
import android.content.Intent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.Shuffle
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.ytlite.player.R
import com.ytlite.player.data.model.DataSource
import com.ytlite.player.playback.QueueItem
import com.ytlite.player.ui.common.ActionMenuRow
import com.ytlite.player.ui.library.LibraryImage
import com.ytlite.player.ui.library.LibraryPlaylistThumbnail
import com.ytlite.player.ui.library.SystemPlaylistIcon
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlaylistActionBottomSheet(
    context: PlaylistActionContext,
    onDismiss: () -> Unit,
    onShufflePlay: (List<QueueItem>) -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
) {
    val application = LocalContext.current.applicationContext as Application
    val viewModel: PlaylistActionViewModel = viewModel(
        key = "playlist-action-${context.playlistId}",
        factory = PlaylistActionViewModel.factory(application, context),
    )
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val androidContext = LocalContext.current
    val scope = rememberCoroutineScope()
    val statsSubtitle = formatPlaylistStatsSubtitle(
        trackCount = uiState.trackCount,
        totalDurationSeconds = uiState.totalDurationSeconds,
    )

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(bottom = 24.dp),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (context.coverUrl.isNullOrBlank() && context.systemType != null) {
                    SystemPlaylistIcon(
                        systemType = context.systemType,
                        modifier = Modifier
                            .size(56.dp)
                            .clip(RoundedCornerShape(8.dp)),
                        iconSize = 28.dp,
                    )
                } else if (context.coverUrl.isNullOrBlank()) {
                    LibraryPlaylistThumbnail(
                        item = com.ytlite.player.data.model.LibraryItem.Playlist(
                            id = context.playlistId,
                            playlistId = context.playlistId,
                            title = context.title,
                            subtitle = "",
                            coverUrl = null,
                            source = context.source,
                            sortKeyActivity = 0L,
                            sortKeySaved = 0L,
                            systemType = context.systemType,
                        ),
                        modifier = Modifier
                            .size(56.dp)
                            .clip(RoundedCornerShape(8.dp)),
                        iconSize = 28.dp,
                    )
                } else {
                    LibraryImage(
                        model = context.coverUrl,
                        contentDescription = context.title,
                        modifier = Modifier
                            .size(56.dp)
                            .clip(RoundedCornerShape(8.dp)),
                    )
                }
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .padding(start = 12.dp),
                ) {
                    Text(
                        text = context.title,
                        style = MaterialTheme.typography.titleMedium,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    if (!uiState.isLoading) {
                        Text(
                            text = statsSubtitle,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

            ActionMenuRow(
                icon = Icons.Outlined.Shuffle,
                label = stringResource(R.string.playlist_action_shuffle_play),
                enabled = uiState.trackCount > 0,
                onClick = {
                    scope.launch {
                        val items = viewModel.loadQueueItems()
                        if (items.isNotEmpty()) {
                            onShufflePlay(items)
                            onDismiss()
                        }
                    }
                },
            )
            ActionMenuRow(
                icon = Icons.Outlined.Edit,
                label = stringResource(R.string.playlist_action_edit),
                enabled = context.canEdit,
                onClick = { onEdit() },
            )
            ActionMenuRow(
                icon = Icons.Outlined.PushPin,
                label = if (uiState.isPinned) {
                    stringResource(R.string.playlist_action_unpin)
                } else {
                    stringResource(R.string.playlist_action_pin)
                },
                enabled = context.canPin,
                onClick = {
                    viewModel.togglePin { }
                },
            )
            ActionMenuRow(
                icon = Icons.Outlined.Share,
                label = stringResource(R.string.library_action_share),
                onClick = {
                    val shareText = buildPlaylistShareText(context)
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, shareText)
                    }
                    androidContext.startActivity(Intent.createChooser(intent, null))
                    onDismiss()
                },
            )

            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

            ActionMenuRow(
                icon = Icons.Outlined.DeleteOutline,
                label = stringResource(R.string.playlist_action_delete),
                enabled = context.canDelete,
                onClick = { onDelete() },
            )
        }
    }
}

@Composable
fun formatPlaylistStatsSubtitle(
    trackCount: Int,
    totalDurationSeconds: Int,
): String {
    val songsLabel = stringResource(R.string.playlist_stats_songs, trackCount)
    if (totalDurationSeconds <= 0) return songsLabel
    val durationLabel = formatPlaylistDuration(totalDurationSeconds)
    return stringResource(R.string.playlist_stats_subtitle, songsLabel, durationLabel)
}

@Composable
private fun formatPlaylistDuration(totalSeconds: Int): String {
    val hours = totalSeconds / 3600
    val minutes = (totalSeconds % 3600) / 60
    return if (hours > 0) {
        stringResource(R.string.playlist_duration_hours, hours, minutes)
    } else {
        stringResource(R.string.playlist_duration_minutes, minutes.coerceAtLeast(1))
    }
}

private fun buildPlaylistShareText(context: PlaylistActionContext): String {
    return when {
        context.source == DataSource.YOUTUBE -> {
            "https://www.youtube.com/playlist?list=${context.playlistId}"
        }
        else -> context.title
    }
}
