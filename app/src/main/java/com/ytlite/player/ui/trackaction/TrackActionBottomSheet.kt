package com.ytlite.player.ui.trackaction

import android.app.Application
import android.content.Intent
import android.widget.Toast
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.PlaylistAdd
import androidx.compose.material.icons.automirrored.outlined.QueueMusic
import androidx.compose.material.icons.outlined.Block
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.PlaylistRemove
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.Subtitles
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.material.icons.outlined.ThumbUpOffAlt
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.ytlite.player.R
import com.ytlite.player.playback.PlayQueueRepository
import com.ytlite.player.ui.library.LibraryImage

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TrackActionBottomSheet(
    context: TrackActionContext,
    onDismiss: () -> Unit,
    onSaveToLibrary: (TrackActionContext) -> Unit,
    onEditMetadata: (TrackActionContext) -> Unit,
    onViewLyrics: (String) -> Unit,
    onRemoveFromQueue: (() -> Unit)? = null,
) {
    val application = LocalContext.current.applicationContext as Application
    val viewModel: TrackActionViewModel = viewModel(
        key = "track-action-${context.videoId}",
        factory = TrackActionViewModel.factory(application, context),
    )
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val androidContext = LocalContext.current

    fun toast(messageRes: Int) {
        Toast.makeText(androidContext, androidContext.getString(messageRes), Toast.LENGTH_SHORT)
            .show()
    }

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
                LibraryImage(
                    model = context.thumbnailUrl,
                    contentDescription = context.title,
                    modifier = Modifier
                        .size(56.dp)
                        .clip(RoundedCornerShape(8.dp)),
                )
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .padding(start = 12.dp),
                ) {
                    Text(
                        text = context.title,
                        style = MaterialTheme.typography.titleMedium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        text = context.channelName,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

            TrackMenuRow(
                icon = if (uiState.isLiked) Icons.Outlined.ThumbUp else Icons.Outlined.ThumbUpOffAlt,
                label = if (uiState.isLiked) {
                    stringResource(R.string.track_action_unlike)
                } else {
                    stringResource(R.string.track_action_like)
                },
                onClick = {
                    val wasLiked = uiState.isLiked
                    viewModel.toggleFavorite()
                    toast(if (wasLiked) R.string.toast_track_unliked else R.string.toast_track_liked)
                    onDismiss()
                },
            )
            TrackMenuRow(
                icon = Icons.AutoMirrored.Outlined.QueueMusic,
                label = stringResource(R.string.library_action_play_next),
                onClick = {
                    PlayQueueRepository.insertNext(context.toQueueItem())
                    toast(R.string.toast_play_next)
                    onDismiss()
                },
            )
            TrackMenuRow(
                icon = Icons.AutoMirrored.Outlined.PlaylistAdd,
                label = stringResource(R.string.library_action_add_queue),
                onClick = {
                    PlayQueueRepository.addToEnd(context.toQueueItem())
                    toast(R.string.toast_add_to_queue)
                    onDismiss()
                },
            )
            TrackMenuRow(
                icon = Icons.Outlined.BookmarkBorder,
                label = stringResource(R.string.track_action_save_to_library),
                onClick = {
                    onSaveToLibrary(context)
                    onDismiss()
                },
            )
            TrackMenuRow(
                icon = Icons.Outlined.Edit,
                label = stringResource(R.string.library_action_edit_metadata),
                onClick = {
                    onEditMetadata(context)
                    onDismiss()
                },
            )
            TrackMenuRow(
                icon = Icons.Outlined.Subtitles,
                label = stringResource(R.string.track_action_view_lyrics),
                onClick = {
                    toast(R.string.toast_opening_lyrics)
                    onViewLyrics(context.videoId)
                    onDismiss()
                },
            )
            TrackMenuRow(
                icon = Icons.Outlined.Share,
                label = stringResource(R.string.library_action_share),
                onClick = {
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(
                            Intent.EXTRA_TEXT,
                            "https://www.youtube.com/watch?v=${context.videoId}",
                        )
                    }
                    androidContext.startActivity(Intent.createChooser(intent, null))
                    toast(R.string.toast_share_ready)
                    onDismiss()
                },
            )
            TrackMenuRow(
                icon = Icons.Outlined.Block,
                label = if (uiState.isNotInterested) {
                    stringResource(R.string.track_action_remove_not_interested)
                } else {
                    stringResource(R.string.track_action_not_interested)
                },
                onClick = {
                    val wasNotInterested = uiState.isNotInterested
                    viewModel.toggleNotInterested()
                    toast(
                        if (wasNotInterested) {
                            R.string.toast_remove_not_interested
                        } else {
                            R.string.toast_not_interested
                        },
                    )
                    onDismiss()
                },
            )

            if (context.showRemoveFromQueue || uiState.canRemoveFromPlaylist) {
                HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
            }
            if (context.showRemoveFromQueue) {
                TrackMenuRow(
                    icon = Icons.Outlined.DeleteOutline,
                    label = stringResource(R.string.player_remove_from_queue),
                    onClick = {
                        onRemoveFromQueue?.invoke()
                        toast(R.string.toast_removed_from_queue)
                        onDismiss()
                    },
                )
            }
            if (uiState.canRemoveFromPlaylist) {
                TrackMenuRow(
                    icon = Icons.Outlined.PlaylistRemove,
                    label = stringResource(R.string.library_action_remove_playlist),
                    onClick = {
                        viewModel.removeFromPlaylist()
                        toast(R.string.toast_removed_from_playlist)
                        onDismiss()
                    },
                )
            }
        }
    }
}

@Composable
private fun TrackMenuRow(
    icon: ImageVector,
    label: String,
    onClick: () -> Unit,
    enabled: Boolean = true,
    subtitle: String? = null,
) {
    val contentColor = if (enabled) {
        MaterialTheme.colorScheme.onSurface
    } else {
        MaterialTheme.colorScheme.onSurfaceVariant
    }
    val iconTint = if (enabled) {
        MaterialTheme.colorScheme.onSurfaceVariant
    } else {
        MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(24.dp),
            tint = iconTint,
        )
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(start = 16.dp),
        ) {
            Text(
                text = label,
                style = MaterialTheme.typography.bodyLarge,
                color = contentColor,
            )
            subtitle?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
