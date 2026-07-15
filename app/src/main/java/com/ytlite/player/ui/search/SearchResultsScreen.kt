package com.ytlite.player.ui.search

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import com.ytlite.player.R
import com.ytlite.player.data.model.SearchResultItem
import com.ytlite.player.data.model.SearchResultTab
import com.ytlite.player.data.model.VideoItem
import com.ytlite.player.ui.library.LibraryImage
import com.ytlite.player.ui.player.toVideoItem
import com.ytlite.player.ui.trackaction.LocalTrackDownloadClick
import com.ytlite.player.ui.trackaction.LocalTrackMoreClick
import com.ytlite.player.ui.trackaction.TrackActionContext

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
    onVideoClick: (VideoItem) -> Unit,
    onChannelClick: (SearchResultItem.Channel) -> Unit,
    onPlaylistClick: (SearchResultItem.Playlist) -> Unit,
    modifier: Modifier = Modifier,
) {
    val density = LocalDensity.current
    // Compact list UI: OEM / accessibility fontScale can inflate list+tabs on devices like vivo.
    val compactDensity = remember(density.density, density.fontScale) {
        Density(
            density = density.density,
            fontScale = density.fontScale.coerceAtMost(1.05f),
        )
    }

    CompositionLocalProvider(LocalDensity provides compactDensity) {
        SearchResultsContent(
            query = query,
            activeTab = activeTab,
            items = items,
            isLoading = isLoading,
            isLoadingMore = isLoadingMore,
            error = error,
            hasMore = hasMore,
            onTabSelected = onTabSelected,
            onLoadMore = onLoadMore,
            onVideoClick = onVideoClick,
            onChannelClick = onChannelClick,
            onPlaylistClick = onPlaylistClick,
            modifier = modifier,
        )
    }
}

@Composable
private fun SearchResultsContent(
    query: String,
    activeTab: SearchResultTab,
    items: List<SearchResultItem>,
    isLoading: Boolean,
    isLoadingMore: Boolean,
    error: String?,
    hasMore: Boolean,
    onTabSelected: (SearchResultTab) -> Unit,
    onLoadMore: () -> Unit,
    onVideoClick: (VideoItem) -> Unit,
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
        TabRow(
            selectedTabIndex = tabs.indexOf(activeTab),
            modifier = Modifier.height(44.dp),
        ) {
            tabs.forEach { tab ->
                Tab(
                    selected = tab == activeTab,
                    onClick = { onTabSelected(tab) },
                    text = {
                        Text(
                            text = tabLabels[tab].orEmpty(),
                            style = MaterialTheme.typography.labelMedium,
                            maxLines = 1,
                            softWrap = false,
                            overflow = TextOverflow.Ellipsis,
                        )
                    },
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
                    Text(
                        text = error,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }
            items.isEmpty() -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(
                        text = stringResource(R.string.search_no_results, query),
                        style = MaterialTheme.typography.bodyMedium,
                    )
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
    onClick: (VideoItem) -> Unit,
) {
    val onTrackMoreClick = LocalTrackMoreClick.current
    val onTrackDownloadClick = LocalTrackDownloadClick.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick(item.toVideoItem()) }
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        LibraryImage(
            model = item.thumbnailUrl,
            contentDescription = item.title,
            modifier = Modifier
                .size(112.dp, 63.dp)
                .clip(RoundedCornerShape(8.dp)),
        )
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(start = 8.dp),
        ) {
            Text(
                text = item.title,
                style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Medium),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = item.subtitle,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        IconButton(
            onClick = { onTrackDownloadClick(item.videoId) },
            modifier = Modifier.size(36.dp),
        ) {
            Icon(
                imageVector = Icons.Outlined.Download,
                contentDescription = stringResource(R.string.library_action_download),
            )
        }
        IconButton(
            onClick = { onTrackMoreClick(TrackActionContext.fromSearchVideo(item)) },
            modifier = Modifier.size(36.dp),
        ) {
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
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        LibraryImage(
            model = item.thumbnailUrl,
            contentDescription = item.title,
            modifier = Modifier
                .size(44.dp)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.surfaceVariant),
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = item.title,
                style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Medium),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            if (item.subtitle.isNotBlank()) {
                Text(
                    text = item.subtitle,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
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
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        LibraryImage(
            model = item.thumbnailUrl,
            contentDescription = item.title,
            modifier = Modifier
                .size(112.dp, 63.dp)
                .clip(RoundedCornerShape(8.dp)),
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = item.title,
                style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Medium),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = item.subtitle,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}
