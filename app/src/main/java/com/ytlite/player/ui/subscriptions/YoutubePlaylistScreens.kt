package com.ytlite.player.ui.subscriptions

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
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
import android.app.Application
import coil.compose.AsyncImage
import com.ytlite.player.R
import com.ytlite.player.data.model.VideoItem
import com.ytlite.player.data.remote.youtube.YoutubeYouPlaylistPreview
import com.ytlite.player.playback.QueueItem
import com.ytlite.player.ui.home.VideoFeedItem
import com.ytlite.player.ui.image.rememberYTLiteImageLoader
import com.ytlite.player.ui.image.thumbnailRequest
import com.ytlite.player.ui.player.toQueueItem

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun YoutubePlaylistItemsScreen(
    playlistId: String,
    title: String,
    onBack: () -> Unit,
    onVideoClick: (VideoItem) -> Unit,
    onPlayPlaylist: (List<QueueItem>, Int, String) -> Unit = { _, _, _ -> },
    modifier: Modifier = Modifier,
) {
    val application = LocalContext.current.applicationContext as Application
    val viewModel: YoutubePlaylistItemsViewModel = viewModel(
        key = playlistId,
        factory = YoutubePlaylistItemsViewModel.factory(application, playlistId, title),
    )
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val imageLoader = rememberYTLiteImageLoader()
    val listState = rememberLazyListState()

    val shouldLoadMore by remember {
        derivedStateOf {
            val layoutInfo = listState.layoutInfo
            val lastVisible = layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
            lastVisible >= layoutInfo.totalItemsCount - 3
        }
    }

    LaunchedEffect(shouldLoadMore, uiState.continuation, uiState.isLoadingMore) {
        if (shouldLoadMore && uiState.continuation != null && !uiState.isLoadingMore) {
            viewModel.loadMore()
        }
    }

    fun playFromPlaylist(video: VideoItem) {
        val queueItems = uiState.videos.map { it.toQueueItem() }
        val startIndex = queueItems.indexOfFirst { it.videoId == video.videoId }.coerceAtLeast(0)
        if (queueItems.isNotEmpty()) {
            onPlayPlaylist(queueItems, startIndex, "yt_playlist:$playlistId")
        } else {
            onVideoClick(video)
        }
    }

    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = title,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                },
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
        PullToRefreshBox(
            isRefreshing = uiState.isLoading && uiState.videos.isNotEmpty(),
            onRefresh = { viewModel.refresh() },
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
        ) {
            when {
                uiState.isLoading && uiState.videos.isEmpty() -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                }
                uiState.errorMessage != null && uiState.videos.isEmpty() -> {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(32.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Text(text = uiState.errorMessage.orEmpty())
                        TextButton(onClick = { viewModel.refresh() }) {
                            Text(text = stringResource(R.string.home_retry))
                        }
                    }
                }
                uiState.videos.isEmpty() -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(
                            text = stringResource(R.string.youtube_you_playlist_items_empty),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                else -> {
                    LazyColumn(
                        state = listState,
                        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        items(items = uiState.videos, key = { it.videoId }) { video ->
                            VideoFeedItem(
                                video = video,
                                imageLoader = imageLoader,
                                onClick = { playFromPlaylist(video) },
                            )
                        }
                        if (uiState.isLoadingMore) {
                            item(key = "loading_more") {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(vertical = 16.dp),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    CircularProgressIndicator()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun YoutubePlaylistsListScreen(
    onBack: () -> Unit,
    onPlaylistClick: (YoutubePlaylistNav) -> Unit,
    modifier: Modifier = Modifier,
) {
    val application = LocalContext.current.applicationContext as Application
    val viewModel: YoutubePlaylistsListViewModel = viewModel(
        factory = YoutubePlaylistsListViewModel.factory(application),
    )
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val imageLoader = rememberYTLiteImageLoader()
    val listState = rememberLazyListState()

    val shouldLoadMore by remember {
        derivedStateOf {
            val layoutInfo = listState.layoutInfo
            val lastVisible = layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
            lastVisible >= layoutInfo.totalItemsCount - 3
        }
    }

    LaunchedEffect(shouldLoadMore, uiState.continuation, uiState.isLoadingMore) {
        if (shouldLoadMore && uiState.continuation != null && !uiState.isLoadingMore) {
            viewModel.loadMore()
        }
    }

    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text(text = stringResource(R.string.youtube_you_playlists)) },
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
        PullToRefreshBox(
            isRefreshing = uiState.isLoading && uiState.playlists.isNotEmpty(),
            onRefresh = { viewModel.refresh() },
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
        ) {
            when {
                uiState.isLoading && uiState.playlists.isEmpty() -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator()
                    }
                }
                uiState.errorMessage != null && uiState.playlists.isEmpty() -> {
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(32.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        Text(text = uiState.errorMessage.orEmpty())
                        TextButton(onClick = { viewModel.refresh() }) {
                            Text(text = stringResource(R.string.home_retry))
                        }
                    }
                }
                uiState.playlists.isEmpty() -> {
                    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        Text(
                            text = stringResource(R.string.youtube_you_playlists_empty),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                else -> {
                    LazyColumn(
                        state = listState,
                        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        items(
                            items = uiState.playlists,
                            key = { it.playlistId },
                        ) { playlist ->
                            YoutubePlaylistListRow(
                                playlist = playlist,
                                imageLoader = imageLoader,
                                onClick = {
                                    onPlaylistClick(
                                        YoutubePlaylistNav(
                                            playlistId = playlist.playlistId,
                                            title = playlist.title,
                                        ),
                                    )
                                },
                            )
                        }
                        if (uiState.isLoadingMore) {
                            item(key = "loading_more") {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(vertical = 16.dp),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    CircularProgressIndicator()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun YoutubePlaylistListRow(
    playlist: YoutubeYouPlaylistPreview,
    imageLoader: coil.ImageLoader,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AsyncImage(
            model = thumbnailRequest(LocalContext.current, playlist.thumbnailUrl.orEmpty()),
            contentDescription = null,
            imageLoader = imageLoader,
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .size(width = 120.dp, height = 68.dp)
                .clip(RoundedCornerShape(8.dp)),
        )
        Column(modifier = Modifier.padding(start = 12.dp)) {
            Text(
                text = playlist.title,
                style = MaterialTheme.typography.titleSmall,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            val meta = buildList {
                playlist.itemCount?.let {
                    add(stringResource(R.string.youtube_you_video_count, it))
                }
                add(stringResource(R.string.youtube_you_playlist_subtitle))
            }.joinToString(" · ")
            Text(
                text = meta,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(top = 4.dp),
            )
        }
    }
}
