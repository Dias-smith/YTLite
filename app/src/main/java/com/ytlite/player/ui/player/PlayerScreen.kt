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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Cast
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.ThumbDown
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.outlined.Notifications
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
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.ytlite.player.R
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
    val playbackError by PlaybackManager.playbackError.collectAsStateWithLifecycle()

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
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .aspectRatio(16f / 9f),
                            ) {
                                VideoPlayerView(
                                    player = sharedPlayer,
                                    modifier = Modifier.fillMaxSize(),
                                )
                                if (playbackError != null) {
                                    Box(
                                        modifier = Modifier
                                            .fillMaxSize()
                                            .padding(16.dp),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        Column(
                                            horizontalAlignment = Alignment.CenterHorizontally,
                                            verticalArrangement = Arrangement.spacedBy(8.dp),
                                        ) {
                                            Text(
                                                text = stringResource(R.string.player_playback_failed),
                                                style = MaterialTheme.typography.titleSmall,
                                                color = MaterialTheme.colorScheme.onSurface,
                                            )
                                            Text(
                                                text = playbackError.orEmpty(),
                                                style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                            )
                                            Button(onClick = { viewModel.loadPlayback() }) {
                                                Text(text = stringResource(R.string.home_retry))
                                            }
                                        }
                                    }
                                }
                            }
                        } else {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .aspectRatio(16f / 9f),
                                contentAlignment = Alignment.Center,
                            ) {
                                CircularProgressIndicator()
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

                            val displayDescription = remember(playback.description, uiState.isDescriptionExpanded) {
                                if (playback.description.isBlank()) return@remember ""
                                val maxChars = if (uiState.isDescriptionExpanded) 8_000 else 400
                                playback.description.take(maxChars)
                            }
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .animateContentSize(),
                            ) {
                                if (displayDescription.isNotBlank()) {
                                    Text(
                                        text = displayDescription,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        maxLines = if (uiState.isDescriptionExpanded) Int.MAX_VALUE else 3,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                }
                                TextButton(onClick = {
                                    if (!uiState.isDescriptionExpanded) {
                                        viewModel.loadFullMetadataIfNeeded()
                                    }
                                    viewModel.toggleDescription()
                                }) {
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

                    item(key = "comments_header") {
                        HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
                        Text(
                            text = stringResource(R.string.player_comments),
                            style = MaterialTheme.typography.titleSmall,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                        )
                    }

                    item(key = "comments_placeholder") {
                        Text(
                            text = stringResource(R.string.player_comments_coming_soon),
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

@Composable
private fun formatViewCount(count: Long): String {
    if (count <= 0L) return ""
    val formatted = NumberFormat.getNumberInstance(Locale.getDefault()).format(count)
    return stringResource(R.string.player_view_count, formatted)
}
