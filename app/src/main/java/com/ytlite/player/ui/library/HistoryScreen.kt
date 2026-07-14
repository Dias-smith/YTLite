package com.ytlite.player.ui.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
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
import com.ytlite.player.data.model.DataSource
import com.ytlite.player.data.model.LibraryVideo
import com.ytlite.player.playback.QueueItem
import com.ytlite.player.ui.player.toQueueItem

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HistoryScreen(
    ownerKey: String,
    onBack: () -> Unit,
    onPlayPlaylist: (List<QueueItem>, Int, String) -> Unit,
    onSongMoreClick: (LibraryVideo, String?, DataSource) -> Unit,
    modifier: Modifier = Modifier,
) {
    val application = LocalContext.current.applicationContext as Application
    val viewModel: HistoryViewModel = viewModel(
        factory = HistoryViewModel.factory(application, ownerKey),
    )
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val flatQueue = remember(uiState.groupedHistory) {
        uiState.groupedHistory.values.flatten().map { it.toQueueItem() }
    }

    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text(text = stringResource(R.string.library_history)) },
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
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
        ) {
            item(key = "yt_unavailable_banner") {
                LibraryYoutubeHistoryUnavailable(
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
                HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
            }
            item(key = "ytlite_label") {
                LibrarySourceLabel(
                    title = stringResource(R.string.library_source_ytlite),
                    modifier = Modifier.padding(horizontal = 16.dp),
                )
            }
            uiState.groupedHistory.forEach { (monthLabel, videos) ->
                item(key = "header_$monthLabel") {
                    Text(
                        text = monthLabel,
                        style = MaterialTheme.typography.titleMedium,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                    )
                }
                items(
                    count = videos.size,
                    key = { index -> "history_${videos[index].videoId}" },
                ) { index ->
                    val video = videos[index]
                    HistoryRow(
                        video = video,
                        onClick = {
                            val startIndex = flatQueue.indexOfFirst { it.videoId == video.videoId }
                                .coerceAtLeast(0)
                            if (flatQueue.isNotEmpty()) {
                                onPlayPlaylist(flatQueue, startIndex, "system:history")
                            }
                        },
                        onMoreClick = {
                            onSongMoreClick(video, null, DataSource.LOCAL)
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun HistoryRow(
    video: LibraryVideo,
    onClick: () -> Unit,
    onMoreClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        LibraryImage(
            model = video.thumbnailUrl,
            contentDescription = video.title,
            modifier = Modifier
                .size(80.dp, 45.dp)
                .clip(RoundedCornerShape(4.dp)),
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = video.title,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = video.channelName,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        IconButton(onClick = onMoreClick) {
            Icon(
                imageVector = Icons.Default.MoreVert,
                contentDescription = stringResource(R.string.library_song_more),
            )
        }
    }
}
