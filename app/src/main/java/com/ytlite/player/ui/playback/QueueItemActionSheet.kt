package com.ytlite.player.ui.playback

import android.content.Intent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import android.app.Application
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.ytlite.player.R
import com.ytlite.player.playback.PlayQueueRepository
import com.ytlite.player.playback.QueueItem
import com.ytlite.player.ui.library.LibraryImage
import com.ytlite.player.ui.library.SongActionContext
import com.ytlite.player.ui.library.SongActionViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QueueItemActionSheet(
    context: SongActionContext,
    showRemoveFromQueue: Boolean,
    onDismiss: () -> Unit,
    onRemoveFromQueue: (() -> Unit)? = null,
) {
    val application = LocalContext.current.applicationContext as Application
    val viewModel: SongActionViewModel = viewModel(
        factory = SongActionViewModel.factory(application, context),
    )
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val androidContext = LocalContext.current

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 24.dp),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                LibraryImage(
                    model = context.thumbnailUrl,
                    contentDescription = context.title,
                    modifier = Modifier
                        .size(56.dp)
                        .clip(RoundedCornerShape(8.dp)),
                )
                Column(modifier = Modifier.weight(1f)) {
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
                IconButton(onClick = { viewModel.toggleFavorite() }) {
                    Icon(
                        imageVector = Icons.Default.ThumbUp,
                        contentDescription = stringResource(R.string.library_like_toggle),
                        tint = if (uiState.isLiked) {
                            MaterialTheme.colorScheme.primary
                        } else {
                            MaterialTheme.colorScheme.onSurfaceVariant
                        },
                    )
                }
            }
            QueueActionRow(
                label = stringResource(R.string.library_action_play_next),
                onClick = {
                    PlayQueueRepository.insertNext(context.toQueueItem())
                    onDismiss()
                },
            )
            QueueActionRow(
                label = stringResource(R.string.library_action_add_queue),
                onClick = {
                    PlayQueueRepository.addToEnd(context.toQueueItem())
                    onDismiss()
                },
            )
            QueueActionRow(
                label = stringResource(R.string.library_action_share),
                onClick = {
                    val intent = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, "https://www.youtube.com/watch?v=${context.videoId}")
                    }
                    androidContext.startActivity(Intent.createChooser(intent, null))
                    onDismiss()
                },
            )
            if (showRemoveFromQueue) {
                HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
                QueueActionRow(
                    label = stringResource(R.string.player_remove_from_queue),
                    onClick = {
                        onRemoveFromQueue?.invoke()
                        onDismiss()
                    },
                )
            }
        }
    }
}

@Composable
private fun QueueActionRow(
    label: String,
    onClick: () -> Unit,
) {
    Text(
        text = label,
        style = MaterialTheme.typography.bodyLarge,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
    )
}

private fun SongActionContext.toQueueItem() = QueueItem(
    videoId = videoId,
    title = title,
    channelName = channelName,
    thumbnailUrl = thumbnailUrl,
)
