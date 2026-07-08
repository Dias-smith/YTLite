package com.ytlite.player.ui.library

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import android.app.Application
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.ytlite.player.R
import com.ytlite.player.data.local.model.PlaylistTrackDetailRow
import com.ytlite.player.data.model.DataSource

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlaylistDetailScreen(
    playlistId: String,
    ownerKey: String,
    systemType: String? = null,
    onBack: () -> Unit,
    onVideoClick: (String) -> Unit,
    onCloneYoutubePlaylist: () -> Unit,
    onSongMoreClick: (PlaylistTrackDetailRow, String, DataSource) -> Unit,
    modifier: Modifier = Modifier,
) {
    val application = LocalContext.current.applicationContext as Application
    val viewModel: PlaylistDetailViewModel = viewModel(
        key = "$ownerKey:${systemType ?: playlistId}",
        factory = PlaylistDetailViewModel.factory(
            application,
            playlistId,
            ownerKey,
            systemType,
        ),
    )
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val playlist = uiState.playlist

    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text(text = playlist?.name.orEmpty()) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.player_back),
                        )
                    }
                },
                actions = {
                    if (playlist?.isYoutube() == true) {
                        IconButton(onClick = onCloneYoutubePlaylist) {
                            Icon(
                                imageVector = Icons.Default.MoreVert,
                                contentDescription = stringResource(R.string.library_clone_to_local),
                            )
                        }
                    }
                },
            )
        },
    ) { innerPadding ->
        if (playlist == null) return@Scaffold

        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
        ) {
            item(key = "header") {
                PlaylistDetailHeader(
                    playlistName = playlist.name,
                    statsText = uiState.statsText,
                    coverUrls = uiState.coverUrls,
                    isLiked = playlist.isLikedSystemPlaylist(),
                    isWatchLater = playlist.isWatchLaterSystemPlaylist(),
                    onPlayFirst = {
                        uiState.tracks.firstOrNull()?.let { onVideoClick(it.trackId) }
                    },
                )
            }
            if (playlist.isLocal()) {
                item(key = "add_song") {
                    Text(
                        text = stringResource(R.string.library_add_song),
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { }
                            .padding(horizontal = 16.dp, vertical = 14.dp),
                    )
                }
            }
            items(
                count = uiState.tracks.size,
                key = { index -> uiState.tracks[index].trackId },
            ) { index ->
                val track = uiState.tracks[index]
                PlaylistTrackRow(
                    track = track,
                    onClick = { onVideoClick(track.trackId) },
                    onMoreClick = {
                        onSongMoreClick(track, playlistId, playlist.dataSource)
                    },
                )
            }
        }
    }
}

@Composable
private fun PlaylistDetailHeader(
    playlistName: String,
    statsText: String,
    coverUrls: List<String>,
    isLiked: Boolean,
    isWatchLater: Boolean,
    onPlayFirst: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        PlaylistCoverArt(
            coverUrls = coverUrls,
            isLiked = isLiked,
            isWatchLater = isWatchLater,
            modifier = Modifier
                .fillMaxWidth(0.55f)
                .aspectRatio(1f),
        )
        Text(
            text = playlistName,
            style = MaterialTheme.typography.headlineSmall,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            text = statsText,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Row(
            horizontalArrangement = Arrangement.spacedBy(24.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = { }, enabled = false) {
                Icon(Icons.Default.Download, contentDescription = null)
            }
            FilledIconButton(
                onClick = onPlayFirst,
                modifier = Modifier.size(64.dp),
                shape = CircleShape,
            ) {
                Icon(
                    imageVector = Icons.Default.PlayArrow,
                    contentDescription = stringResource(R.string.library_play_all),
                    modifier = Modifier.size(32.dp),
                )
            }
            IconButton(onClick = { }) {
                Icon(Icons.Default.MoreVert, contentDescription = null)
            }
        }
    }
}

@Composable
private fun PlaylistCoverArt(
    coverUrls: List<String>,
    isLiked: Boolean,
    isWatchLater: Boolean,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier.clip(RoundedCornerShape(8.dp)),
        contentAlignment = Alignment.Center,
    ) {
        when {
            isLiked -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(
                            Brush.linearGradient(
                                colors = listOf(Color(0xFF4FC3F7), Color(0xFFE91E63)),
                            ),
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Default.ThumbUp,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier.size(64.dp),
                    )
                }
            }
            isWatchLater -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(MaterialTheme.colorScheme.primaryContainer),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Default.Schedule,
                        contentDescription = null,
                        modifier = Modifier.size(64.dp),
                    )
                }
            }
            coverUrls.size >= 4 -> {
                Column(modifier = Modifier.fillMaxSize()) {
                    Row(modifier = Modifier.weight(1f)) {
                        LibraryImage(coverUrls[0], null, Modifier.weight(1f).fillMaxSize())
                        LibraryImage(coverUrls[1], null, Modifier.weight(1f).fillMaxSize())
                    }
                    Row(modifier = Modifier.weight(1f)) {
                        LibraryImage(coverUrls[2], null, Modifier.weight(1f).fillMaxSize())
                        LibraryImage(coverUrls[3], null, Modifier.weight(1f).fillMaxSize())
                    }
                }
            }
            coverUrls.isNotEmpty() -> {
                LibraryImage(
                    model = coverUrls.first(),
                    contentDescription = null,
                    modifier = Modifier.fillMaxSize(),
                )
            }
            else -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(MaterialTheme.colorScheme.surfaceVariant),
                )
            }
        }
    }
}

@Composable
private fun PlaylistTrackRow(
    track: PlaylistTrackDetailRow,
    onClick: () -> Unit,
    onMoreClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        LibraryImage(
            model = track.thumbnailUrl,
            contentDescription = track.title,
            modifier = Modifier
                .size(48.dp)
                .clip(RoundedCornerShape(4.dp)),
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = track.title,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = track.primaryArtistName.orEmpty(),
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
