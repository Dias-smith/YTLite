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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import android.app.Application
import androidx.compose.ui.platform.LocalContext
import com.ytlite.player.R
import com.ytlite.player.data.model.LibraryVideo
import com.ytlite.player.data.model.VideoItem
import com.ytlite.player.ui.player.toVideoItem
import com.ytlite.player.ui.trackaction.LocalTrackMoreClick
import com.ytlite.player.ui.trackaction.TrackActionContext

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AlbumTracksScreen(
    albumName: String,
    ownerKey: String,
    onBack: () -> Unit,
    onVideoClick: (VideoItem) -> Unit,
    modifier: Modifier = Modifier,
) {
    val application = LocalContext.current.applicationContext as Application
    val viewModel: AlbumTracksViewModel = viewModel(
        key = "album-$albumName",
        factory = AlbumTracksViewModel.factory(application, ownerKey, albumName),
    )
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val onTrackMoreClick = LocalTrackMoreClick.current

    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text(albumName, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
                    }
                },
            )
        },
    ) { innerPadding ->
        if (uiState.tracks.isEmpty()) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding)
                    .padding(24.dp),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    text = stringResource(R.string.album_tracks_empty),
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding),
            ) {
                items(uiState.tracks, key = { it.videoId }) { video ->
                    AlbumTrackRow(
                        video = video,
                        onClick = { onVideoClick(video.toVideoItem()) },
                        onMoreClick = {
                            onTrackMoreClick(TrackActionContext.fromLibraryVideo(video))
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun AlbumTrackRow(
    video: LibraryVideo,
    onClick: () -> Unit,
    onMoreClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        LibraryImage(
            model = video.thumbnailUrl,
            contentDescription = video.title,
            modifier = Modifier
                .size(56.dp)
                .clip(RoundedCornerShape(8.dp)),
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = video.title,
                style = MaterialTheme.typography.bodyLarge,
                maxLines = 1,
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
            Icon(Icons.Default.MoreVert, contentDescription = stringResource(R.string.library_song_more))
        }
    }
}
