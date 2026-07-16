package com.ytlite.player.ui.search

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.History
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.ytlite.player.R
import com.ytlite.player.data.local.entity.SearchQueryEntity
import com.ytlite.player.data.local.entity.SearchRecentClickEntity
import com.ytlite.player.data.model.SearchRecentType
import com.ytlite.player.ui.library.LibraryImage

@Composable
fun DefaultHubView(
    recentClicks: List<SearchRecentClickEntity>,
    queryHistory: List<SearchQueryEntity>,
    hotKeywords: List<String>,
    onRecentClick: (SearchRecentClickEntity) -> Unit,
    onRecentLongPress: (String) -> Unit,
    onClearRecentClicks: () -> Unit,
    onHistoryQueryClick: (String) -> Unit,
    onClearQueryHistory: () -> Unit,
    onHotKeywordClick: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = 16.dp),
    ) {
        if (recentClicks.isNotEmpty()) {
            item(key = "recent_header") {
                SectionHeader(
                    title = stringResource(R.string.search_recent_searches),
                    onClear = onClearRecentClicks,
                    modifier = Modifier.padding(top = 4.dp),
                )
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
                SectionHeader(
                    title = stringResource(R.string.search_history),
                    onClear = onClearQueryHistory,
                    modifier = Modifier.padding(top = if (recentClicks.isNotEmpty()) 8.dp else 4.dp),
                )
            }
            items(queryHistory, key = { "history_${it.query}" }) { entity ->
                HistoryQueryRow(
                    query = entity.query,
                    onClick = { onHistoryQueryClick(entity.query) },
                )
            }
        }

        if (hotKeywords.isNotEmpty()) {
            item(key = "hot_header") {
                Text(
                    text = stringResource(R.string.search_hot_keywords),
                    style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold),
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.padding(
                        start = 16.dp,
                        end = 16.dp,
                        top = if (queryHistory.isNotEmpty() || recentClicks.isNotEmpty()) 10.dp else 4.dp,
                        bottom = 8.dp,
                    ),
                )
            }
            item(key = "hot_chips") {
                HotKeywordChipGroup(
                    keywords = hotKeywords,
                    onKeywordClick = onHotKeywordClick,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp),
                )
            }
        }
    }
}

@Composable
private fun SectionHeader(
    title: String,
    onClear: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .heightIn(min = 32.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold),
            color = MaterialTheme.colorScheme.onSurface,
        )
        TextButton(
            onClick = onClear,
            contentPadding = PaddingValues(horizontal = 8.dp, vertical = 0.dp),
            modifier = Modifier.heightIn(min = 32.dp),
        ) {
            Text(
                text = stringResource(R.string.search_clear_all),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
            )
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
                        when (entity.type) {
                            SearchRecentType.CHANNEL.name -> CircleShape
                            else -> RoundedCornerShape(8.dp)
                        },
                    ),
            )
            Text(
                text = entity.title,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurface,
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
            modifier = Modifier.size(22.dp),
        )
        Text(
            text = query,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier
                .weight(1f)
                .padding(start = 12.dp),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun HotKeywordChipGroup(
    keywords: List<String>,
    onKeywordClick: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    FlowRow(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        keywords.forEach { keyword ->
            HotKeywordChip(
                keyword = keyword,
                onClick = { onKeywordClick(keyword) },
            )
        }
    }
}

@Composable
private fun HotKeywordChip(
    keyword: String,
    onClick: () -> Unit,
) {
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(50),
        color = MaterialTheme.colorScheme.surfaceVariant,
        contentColor = MaterialTheme.colorScheme.onSurface,
    ) {
        Text(
            text = keyword,
            style = MaterialTheme.typography.bodyMedium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 8.dp),
        )
    }
}
