package com.ytlite.player.ui.player

import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Cast
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.ThumbDown
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.ytlite.player.R
import com.ytlite.player.data.model.StreamFormat
import com.ytlite.player.playback.PlaybackManager
import java.text.NumberFormat
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlayerScreen(
    onBack: () -> Unit,
    viewModel: PlayerViewModel,
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val sharedPlayer by PlaybackManager.playerState.collectAsStateWithLifecycle()

    if (uiState.showFormatPicker && uiState.playback != null) {
        FormatPickerDialog(
            formats = uiState.playback!!.formats,
            onFormatSelected = viewModel::selectFormat,
        )
    }

    if (uiState.showStreamUrlDialog && uiState.selectedStreamUrl != null) {
        AlertDialog(
            onDismissRequest = viewModel::dismissStreamUrlDialog,
            title = {
                Text(text = stringResource(R.string.player_stream_url_title))
            },
            text = {
                Text(
                    text = uiState.selectedStreamUrl!!,
                    style = MaterialTheme.typography.bodySmall,
                    modifier = Modifier.verticalScroll(rememberScrollState()),
                )
            },
            confirmButton = {
                TextButton(onClick = viewModel::dismissStreamUrlDialog) {
                    Text(text = stringResource(R.string.player_stream_url_close))
                }
            },
        )
    }

    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.player_back),
                        )
                    }
                },
            )
        },
    ) { innerPadding ->
        when {
            uiState.isLoading -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }
            uiState.errorMessage != null -> {
                ErrorContent(
                    message = uiState.errorMessage.orEmpty(),
                    onRetry = { viewModel.loadPlayback() },
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding),
                )
            }
            uiState.playback != null -> {
                val playback = requireNotNull(uiState.playback)
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding),
                ) {
                    item(key = "player_surface") {
                        if (uiState.selectedStreamUrl != null) {
                            VideoPlayerView(
                                player = sharedPlayer,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .aspectRatio(16f / 9f),
                            )
                        } else {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .aspectRatio(16f / 9f),
                                contentAlignment = Alignment.Center,
                            ) {
                                Text(
                                    text = stringResource(R.string.player_select_format_hint),
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }

                    item(key = "video_meta") {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp, vertical = 12.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Text(
                                text = playback.title,
                                style = MaterialTheme.typography.titleMedium,
                            )
                            Text(
                                text = formatViewCount(playback.viewCount),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            Text(
                                text = playback.channelName,
                                style = MaterialTheme.typography.bodyMedium,
                            )

                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                ActionIconButton(
                                    icon = { Icon(Icons.Filled.ThumbUp, contentDescription = null) },
                                    label = stringResource(R.string.player_like),
                                )
                                ActionIconButton(
                                    icon = { Icon(Icons.Filled.ThumbDown, contentDescription = null) },
                                    label = stringResource(R.string.player_dislike),
                                )
                                ActionIconButton(
                                    icon = { Icon(Icons.Outlined.Notifications, contentDescription = null) },
                                    label = stringResource(R.string.player_subscribe),
                                )
                                ActionIconButton(
                                    icon = { Icon(Icons.Filled.Share, contentDescription = null) },
                                    label = stringResource(R.string.player_share),
                                )
                                ActionIconButton(
                                    icon = { Icon(Icons.Filled.Cast, contentDescription = null) },
                                    label = stringResource(R.string.player_cast),
                                )
                            }

                            if (playback.description.isNotBlank()) {
                                Column(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .animateContentSize(),
                                ) {
                                    Text(
                                        text = playback.description,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        maxLines = if (uiState.isDescriptionExpanded) Int.MAX_VALUE else 3,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                    TextButton(onClick = { viewModel.toggleDescription() }) {
                                        Text(
                                            text = if (uiState.isDescriptionExpanded) {
                                                stringResource(R.string.player_show_less)
                                            } else {
                                                stringResource(R.string.player_show_more)
                                            },
                                        )
                                    }
                                }
                            }
                        }
                    }

                    item(key = "comments_header") {
                        HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
                        Text(
                            text = stringResource(R.string.player_comments),
                            style = MaterialTheme.typography.titleSmall,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                        )
                    }

                    items(
                        items = placeholderComments,
                        key = { it },
                    ) { comment ->
                        Text(
                            text = comment,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun FormatPickerDialog(
    formats: List<StreamFormat>,
    onFormatSelected: (StreamFormat) -> Unit,
) {
    AlertDialog(
        onDismissRequest = { },
        title = {
            Text(text = stringResource(R.string.player_format_picker_title))
        },
        text = {
            LazyColumn(
                modifier = Modifier.heightIn(max = 400.dp),
            ) {
                items(
                    items = formats,
                    key = { "${it.itag}-${it.url}" },
                ) { format ->
                    FormatPickerRow(
                        format = format,
                        onClick = { onFormatSelected(format) },
                    )
                }
            }
        },
        confirmButton = { },
    )
}

@Composable
private fun FormatPickerRow(
    format: StreamFormat,
    onClick: () -> Unit,
) {
    val yes = stringResource(R.string.player_format_yes)
    val no = stringResource(R.string.player_format_no)
    val resolution = formatResolutionLabel(format)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = 12.dp, horizontal = 4.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(
            text = stringResource(R.string.player_format_itag, format.itag),
            style = MaterialTheme.typography.bodyMedium,
        )
        Text(
            text = stringResource(R.string.player_format_resolution, resolution),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = stringResource(
                R.string.player_format_has_audio,
                if (format.hasAudio) yes else no,
            ),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = stringResource(
                R.string.player_format_has_video,
                if (format.hasVideo) yes else no,
            ),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun formatResolutionLabel(format: StreamFormat): String {
    return when {
        format.height > 0 && format.width > 0 -> "${format.height}p (${format.width}×${format.height})"
        format.height > 0 -> "${format.height}p"
        format.hasAudio && !format.hasVideo -> stringResource(R.string.player_format_audio_only)
        else -> "-"
    }
}

@Composable
private fun ActionIconButton(
    icon: @Composable () -> Unit,
    label: String,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.padding(horizontal = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        IconButton(onClick = { }) {
            icon()
        }
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun ErrorContent(
    message: String,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(modifier = modifier, contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.padding(24.dp),
        ) {
            Text(
                text = stringResource(R.string.player_error),
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                text = message,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Button(onClick = onRetry) {
                Text(text = stringResource(R.string.home_retry))
            }
        }
    }
}

private fun formatViewCount(count: Long): String {
    if (count <= 0L) return ""
    return NumberFormat.getNumberInstance(Locale.getDefault()).format(count) + " 次观看"
}

private val placeholderComments = listOf(
    "评论功能即将推出…",
)
