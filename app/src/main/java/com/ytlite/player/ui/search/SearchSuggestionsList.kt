package com.ytlite.player.ui.search

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.ytlite.player.data.model.SearchSuggestion
import com.ytlite.player.ui.library.LibraryImage

@Composable
fun SearchSuggestionsList(
    suggestions: List<SearchSuggestion>,
    isLoading: Boolean,
    onSuggestionClick: (SearchSuggestion) -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(modifier = modifier.fillMaxSize()) {
        LazyColumn(modifier = Modifier.fillMaxSize()) {
            items(
                items = suggestions,
                key = { it.id },
                contentType = { suggestion ->
                    when (suggestion) {
                        is SearchSuggestion.Query -> "query"
                        is SearchSuggestion.Channel -> "channel"
                        is SearchSuggestion.Video -> "video"
                    }
                },
            ) { suggestion ->
                when (suggestion) {
                    is SearchSuggestion.Query -> QuerySuggestionRow(suggestion, onSuggestionClick)
                    is SearchSuggestion.Channel -> ChannelSuggestionRow(suggestion, onSuggestionClick)
                    is SearchSuggestion.Video -> VideoSuggestionRow(suggestion, onSuggestionClick)
                }
                HorizontalDivider()
            }
        }
        if (isLoading && suggestions.isEmpty()) {
            CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
        }
    }
}

@Composable
private fun QuerySuggestionRow(
    suggestion: SearchSuggestion.Query,
    onClick: (SearchSuggestion) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick(suggestion) }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = Icons.Default.History,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = suggestion.text,
            modifier = Modifier.padding(start = 12.dp),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun ChannelSuggestionRow(
    suggestion: SearchSuggestion.Channel,
    onClick: (SearchSuggestion) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick(suggestion) }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        LibraryImage(
            model = suggestion.avatarUrl,
            contentDescription = suggestion.title,
            modifier = Modifier
                .size(40.dp)
                .clip(CircleShape),
        )
        Column(modifier = Modifier
            .weight(1f)
            .padding(horizontal = 12.dp)) {
            Text(text = suggestion.title, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (suggestion.subtitle.isNotBlank()) {
                Text(
                    text = suggestion.subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun VideoSuggestionRow(
    suggestion: SearchSuggestion.Video,
    onClick: (SearchSuggestion) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick(suggestion) }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        LibraryImage(
            model = suggestion.thumbnailUrl,
            contentDescription = suggestion.title,
            modifier = Modifier
                .size(56.dp, 40.dp)
                .clip(RoundedCornerShape(4.dp)),
        )
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = 12.dp),
        ) {
            Text(text = suggestion.title, maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (suggestion.subtitle.isNotBlank()) {
                Text(
                    text = suggestion.subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        IconButton(onClick = { }, enabled = false) {
            Icon(Icons.Default.MoreVert, contentDescription = null)
        }
    }
}
