package com.ytlite.player.ui.search

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.NorthWest
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.ytlite.player.data.local.entity.SearchQueryEntity
import com.ytlite.player.data.local.entity.SearchRecentClickEntity
import com.ytlite.player.data.model.DiscoveryType
import com.ytlite.player.data.model.SearchRecentType
import com.ytlite.player.ui.library.LibraryImage
import androidx.compose.ui.res.stringResource
import com.ytlite.player.R

@Composable
fun DefaultHubView(
    recentClicks: List<SearchRecentClickEntity>,
    queryHistory: List<SearchQueryEntity>,
    onRecentClick: (SearchRecentClickEntity) -> Unit,
    onRecentLongPress: (String) -> Unit,
    onClearRecentClicks: () -> Unit,
    onHistoryQueryClick: (String) -> Unit,
    onClearQueryHistory: () -> Unit,
    onDiscoveryOpen: (DiscoveryType) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = 16.dp),
    ) {
        if (recentClicks.isNotEmpty()) {
            item(key = "recent_header") {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = stringResource(R.string.search_recent_searches),
                        style = MaterialTheme.typography.titleMedium,
                    )
                    TextButton(onClick = onClearRecentClicks) {
                        Text(stringResource(R.string.search_clear_all))
                    }
                }
            }
            item(key = "recent_row") {
                LazyRow(
                    contentPadding = PaddingValues(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    items(recentClicks, key = { it.targetId }) { recent ->
                        RecentClickCard(
                            entity = recent,
                            onClick = { onRecentClick(recent) },
                            onLongClick = { onRecentLongPress(recent.targetId) },
                        )
                    }
                }
            }
        }

        if (queryHistory.isNotEmpty()) {
            item(key = "history_header") {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = stringResource(R.string.search_history),
                        style = MaterialTheme.typography.titleMedium,
                    )
                    TextButton(onClick = onClearQueryHistory) {
                        Text(stringResource(R.string.search_clear_all))
                    }
                }
            }
            items(queryHistory, key = { it.query }) { entity ->
                HistoryQueryRow(
                    query = entity.query,
                    onClick = { onHistoryQueryClick(entity.query) },
                )
            }
        }

        item(key = "discovery_header") {
            Text(
                text = stringResource(R.string.search_discovery),
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            )
        }
        item(key = "discovery_cards") {
            Column(
                modifier = Modifier.padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                DiscoveryCard(
                    title = stringResource(R.string.search_new_releases),
                    subtitle = stringResource(R.string.search_new_releases_sub),
                    onClick = { onDiscoveryOpen(DiscoveryType.NEW_RELEASES) },
                )
                DiscoveryCard(
                    title = stringResource(R.string.search_charts),
                    subtitle = stringResource(R.string.search_charts_sub),
                    onClick = { onDiscoveryOpen(DiscoveryType.CHARTS) },
                )
                DiscoveryCard(
                    title = stringResource(R.string.search_moods),
                    subtitle = stringResource(R.string.search_moods_sub),
                    onClick = { onDiscoveryOpen(DiscoveryType.MOODS_AND_GENRES) },
                )
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun RecentClickCard(
    entity: SearchRecentClickEntity,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
) {
    Card(
        modifier = Modifier
            .width(140.dp)
            .combinedClickable(onClick = onClick, onLongClick = onLongClick),
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Column(modifier = Modifier.padding(8.dp)) {
            LibraryImage(
                model = entity.thumbnailUrl.takeIf { it.isNotBlank() },
                contentDescription = entity.title,
                modifier = Modifier
                    .size(124.dp)
                    .clip(
                        if (entity.type == SearchRecentType.CHANNEL.name) {
                            androidx.compose.foundation.shape.CircleShape
                        } else {
                            RoundedCornerShape(8.dp)
                        },
                    ),
            )
            Text(
                text = entity.title,
                style = MaterialTheme.typography.bodySmall,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.padding(top = 6.dp),
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun HistoryQueryRow(
    query: String,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .combinedClickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = Icons.Default.History,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = query,
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = 12.dp),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        IconButton(onClick = onClick) {
            Icon(Icons.Default.NorthWest, contentDescription = stringResource(R.string.search_fill_query))
        }
    }
}

@Composable
private fun DiscoveryCard(
    title: String,
    subtitle: String,
    onClick: () -> Unit,
) {
    Card(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(text = title, style = MaterialTheme.typography.titleMedium)
            Text(
                text = subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp),
            )
        }
    }
}
