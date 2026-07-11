package com.ytlite.player.ui.search

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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import com.ytlite.player.R
import com.ytlite.player.ui.trackaction.LocalTrackMoreClick
import com.ytlite.player.ui.trackaction.TrackActionContext
import com.ytlite.player.data.model.SearchResultItem
import com.ytlite.player.data.model.SearchResultTab
import com.ytlite.player.ui.library.LibraryImage

@Composable
fun SearchResultsScreen(
    query: String,
    activeTab: SearchResultTab,
    items: List<SearchResultItem>,
    isLoading: Boolean,
    isLoadingMore: Boolean,
    error: String?,
    hasMore: Boolean,
    onTabSelected: (SearchResultTab) -> Unit,
    onLoadMore: () -> Unit,
    onVideoClick: (String) -> Unit,
    onChannelClick: (SearchResultItem.Channel) -> Unit,
    onPlaylistClick: (SearchResultItem.Playlist) -> Unit,
    modifier: Modifier = Modifier,
) {
    val tabs = SearchResultTab.entries
    val tabLabels = mapOf(
        SearchResultTab.ALL to stringResource(R.string.search_tab_all),
        SearchResultTab.VIDEOS to stringResource(R.string.search_tab_videos),
        SearchResultTab.CHANNELS to stringResource(R.string.search_tab_channels),
        SearchResultTab.PLAYLISTS to stringResource(R.string.search_tab_playlists),
    )
    val listState = rememberLazyListState()
    val shouldLoadMore by remember {
        derivedStateOf {
            val lastVisible = listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
            lastVisible >= listState.layoutInfo.totalItemsCount - 3
        }
    }

    LaunchedEffect(shouldLoadMore, hasMore, isLoadingMore) {
        if (shouldLoadMore && hasMore && !isLoadingMore && !isLoading) {
            onLoadMore()
        }
    }

    Column(modifier = modifier.fillMaxSize()) {
        TabRow(selectedTabIndex = tabs.indexOf(activeTab)) {
            tabs.forEach { tab ->
                Tab(
                    selected = tab == activeTab,
                    onClick = { onTabSelected(tab) },
                    text = { Text(tabLabels[tab].orEmpty()) },
                )
            }
        }

        when {
            isLoading && items.isEmpty() -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            }
            error != null && items.isEmpty() -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(error, color = MaterialTheme.colorScheme.error)
                }
            }
            items.isEmpty() -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(stringResource(R.string.search_no_results, query))
                }
            }
            else -> {
                LazyColumn(
                    state = listState,
                    contentPadding = PaddingValues(bottom = 16.dp),
                ) {
                    items(items, key = { it.id }, contentType = { it::class.simpleName }) { item ->
                        when (item) {
                            is SearchResultItem.Video -> VideoResultRow(item, onVideoClick)
                            is SearchResultItem.Channel -> ChannelResultRow(item, onChannelClick)
                            is SearchResultItem.Playlist -> PlaylistResultRow(item, onPlaylistClick)
                        }
                    }
                    if (isLoadingMore) {
                        item(key = "loading_more") {
                            Box(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(16.dp),
                                contentAlignment = Alignment.Center,
                            ) {
                                CircularProgressIndicator(modifier = Modifier.size(24.dp))
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun VideoResultRow(
    item: SearchResultItem.Video,
    onClick: (String) -> Unit,
) {
    val onTrackMoreClick = LocalTrackMoreClick.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick(item.videoId) }
            .padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        LibraryImage(
            model = item.thumbnailUrl,
            contentDescription = item.title,
            modifier = Modifier
                .size(120.dp, 68.dp)
                .clip(RoundedCornerShape(8.dp)),
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(item.title, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(
                text = item.subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
        IconButton(onClick = { onTrackMoreClick(TrackActionContext.fromSearchVideo(item)) }) {
            Icon(Icons.Default.MoreVert, contentDescription = stringResource(R.string.library_song_more))
        }
    }
}

@Composable
private fun ChannelResultRow(
    item: SearchResultItem.Channel,
    onClick: (SearchResultItem.Channel) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick(item) }
            .padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        LibraryImage(
            model = item.thumbnailUrl,
            contentDescription = item.title,
            modifier = Modifier
                .size(48.dp)
                .clip(CircleShape),
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(item.title, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (item.subtitle.isNotBlank()) {
                Text(
                    text = item.subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun PlaylistResultRow(
    item: SearchResultItem.Playlist,
    onClick: (SearchResultItem.Playlist) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick(item) }
            .padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        LibraryImage(
            model = item.thumbnailUrl,
            contentDescription = item.title,
            modifier = Modifier
                .size(120.dp, 68.dp)
                .clip(RoundedCornerShape(8.dp)),
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(item.title, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(
                text = item.subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
