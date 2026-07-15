package com.ytlite.player.ui.download

import android.app.Application
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import com.ytlite.player.R
import com.ytlite.player.data.local.entity.DownloadTaskEntity
import com.ytlite.player.data.local.entity.DownloadTaskStatus
import com.ytlite.player.data.local.entity.DownloadedItemEntity
import com.ytlite.player.playback.QueueItem
import com.ytlite.player.ui.image.thumbnailRequest
import com.ytlite.player.ui.player.formatPlaybackTime
import java.util.Locale
import kotlin.math.max

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DownloadsHubScreen(
    onBack: () -> Unit,
    onSettingsClick: () -> Unit,
    onPlayDownloaded: (List<QueueItem>, Int) -> Unit,
    modifier: Modifier = Modifier,
    viewModel: DownloadsHubViewModel = viewModel(
        factory = DownloadsHubViewModel.factory(
            LocalContext.current.applicationContext as Application,
        ),
    ),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    var selectedTab by remember { mutableIntStateOf(0) }
    val context = LocalContext.current

    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.downloads_title)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.player_back),
                        )
                    }
                },
                actions = {
                    IconButton(onClick = onSettingsClick) {
                        Icon(
                            imageVector = Icons.Outlined.Settings,
                            contentDescription = stringResource(R.string.settings_title),
                        )
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            TabRow(selectedTabIndex = selectedTab) {
                Tab(
                    selected = selectedTab == 0,
                    onClick = { selectedTab = 0 },
                    text = { Text(stringResource(R.string.downloads_tab_library)) },
                )
                Tab(
                    selected = selectedTab == 1,
                    onClick = { selectedTab = 1 },
                    text = { Text(stringResource(R.string.downloads_tab_tasks)) },
                )
            }
            when (selectedTab) {
                0 -> {
                    if (uiState.downloaded.isEmpty()) {
                        EmptyMessage(
                            text = stringResource(R.string.downloads_library_empty),
                            modifier = Modifier.fillMaxSize(),
                        )
                    } else {
                        LazyColumn(
                            modifier = Modifier.fillMaxSize(),
                            contentPadding = PaddingValues(vertical = 8.dp),
                        ) {
                            items(uiState.downloaded, key = { it.id }) { item ->
                                DownloadedRow(
                                    item = item,
                                    onClick = {
                                        val queue = viewModel.downloadedToQueue(uiState.downloaded, 0)
                                        val index = queue.indexOfFirst { it.videoId == item.videoId }
                                            .coerceAtLeast(0)
                                        onPlayDownloaded(queue, index)
                                    },
                                    onDelete = { viewModel.deleteDownloaded(item.id) },
                                )
                                HorizontalDivider()
                            }
                        }
                    }
                }
                else -> {
                    if (uiState.tasks.isEmpty()) {
                        EmptyMessage(
                            text = stringResource(R.string.downloads_tasks_empty),
                            modifier = Modifier.fillMaxSize(),
                        )
                    } else {
                        LazyColumn(
                            modifier = Modifier.fillMaxSize(),
                            contentPadding = PaddingValues(vertical = 8.dp),
                        ) {
                            items(uiState.tasks, key = { it.id }) { task ->
                                DownloadTaskRow(
                                    task = task,
                                    onPause = { viewModel.pause(task.id) },
                                    onResume = { viewModel.resume(task.id) },
                                    onCancel = { viewModel.cancel(task.id) },
                                    onRetry = { viewModel.retry(task.id) },
                                )
                                HorizontalDivider()
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun EmptyMessage(text: String, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.padding(32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun DownloadTaskRow(
    task: DownloadTaskEntity,
    onPause: () -> Unit,
    onResume: () -> Unit,
    onCancel: () -> Unit,
    onRetry: () -> Unit,
) {
    val progress = if (task.totalBytes > 0) {
        (task.downloadedBytes.toFloat() / task.totalBytes.toFloat()).coerceIn(0f, 1f)
    } else {
        0f
    }
    val statusLabel = when (task.status) {
        DownloadTaskStatus.RUNNING -> stringResource(R.string.download_status_running)
        DownloadTaskStatus.QUEUED -> stringResource(R.string.download_status_queued)
        DownloadTaskStatus.PAUSED -> stringResource(R.string.download_status_paused)
        DownloadTaskStatus.FAILED -> stringResource(R.string.download_status_failed)
        else -> task.status
    }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            AsyncImage(
                model = thumbnailRequest(LocalContext.current, task.thumbnailUrl.orEmpty()),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .size(56.dp)
                    .clip(RoundedCornerShape(8.dp)),
            )
            Spacer(modifier = Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = task.title,
                    style = MaterialTheme.typography.bodyLarge,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = "$statusLabel · ${downloadFormatLabel(task.itag, task.mimeType)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (task.totalBytes > 0) {
                    Text(
                        text = formatBytes(task.downloadedBytes) + " / " + formatBytes(task.totalBytes),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            when (task.status) {
                DownloadTaskStatus.RUNNING -> {
                    IconButton(onClick = onPause) {
                        Icon(Icons.Outlined.Pause, contentDescription = null)
                    }
                }
                DownloadTaskStatus.PAUSED, DownloadTaskStatus.QUEUED -> {
                    IconButton(onClick = onResume) {
                        Icon(Icons.Outlined.PlayArrow, contentDescription = null)
                    }
                }
                DownloadTaskStatus.FAILED -> {
                    IconButton(onClick = onRetry) {
                        Icon(Icons.Outlined.Refresh, contentDescription = null)
                    }
                }
            }
            IconButton(onClick = onCancel) {
                Icon(Icons.Outlined.Close, contentDescription = null)
            }
        }
        if (task.status == DownloadTaskStatus.RUNNING || task.status == DownloadTaskStatus.PAUSED) {
            Spacer(modifier = Modifier.height(8.dp))
            LinearProgressIndicator(
                progress = { progress },
                modifier = Modifier.fillMaxWidth(),
                color = MaterialTheme.colorScheme.primary,
            )
        }
        if (task.status == DownloadTaskStatus.FAILED && !task.errorMessage.isNullOrBlank()) {
            Text(
                text = task.errorMessage,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.error,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun DownloadedRow(
    item: DownloadedItemEntity,
    onClick: () -> Unit,
    onDelete: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AsyncImage(
            model = thumbnailRequest(LocalContext.current, item.thumbnailUrl.orEmpty()),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .size(56.dp)
                .clip(RoundedCornerShape(8.dp)),
        )
        Spacer(modifier = Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = item.title,
                style = MaterialTheme.typography.bodyLarge,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = item.channelName,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = buildDownloadedMeta(item.contentLength, item.durationSeconds),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        IconButton(onClick = onDelete) {
            Icon(
                imageVector = Icons.Outlined.Delete,
                contentDescription = stringResource(R.string.library_batch_delete),
            )
        }
    }
}

private fun buildDownloadedMeta(contentLength: Long, durationSeconds: Long): String {
    val size = formatBytes(contentLength)
    if (durationSeconds <= 0L) return size
    return size + " · " + formatPlaybackTime(durationSeconds * 1_000L)
}

@Composable
private fun downloadFormatLabel(itag: Int, mimeType: String): String {
    return when (itag) {
        139 -> stringResource(R.string.track_download_music_fast)
        140 -> stringResource(R.string.track_download_music_classic)
        141 -> stringResource(R.string.track_download_music_high)
        18 -> stringResource(R.string.track_download_video_fast_360)
        22 -> stringResource(R.string.track_download_video_high_720)
        37 -> stringResource(R.string.track_download_video_best_1080)
        else -> {
            val mime = mimeType.lowercase(Locale.US)
            when {
                mime.startsWith("audio") -> stringResource(R.string.download_format_audio)
                mime.startsWith("video") -> stringResource(R.string.download_format_video)
                else -> stringResource(R.string.download_format_file)
            }
        }
    }
}

private fun formatBytes(bytes: Long): String {
    if (bytes <= 0L) return "—"
    val mb = bytes / (1024.0 * 1024.0)
    return if (mb >= 10) {
        String.format(Locale.US, "%.0f MB", mb)
    } else {
        String.format(Locale.US, "%.1f MB", max(0.1, mb))
    }
}
