package com.ytlite.player.ui.search

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.NorthWest
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.ytlite.player.R
import com.ytlite.player.data.model.SearchSuggestion

@Composable
fun SearchSuggestionsList(
    suggestions: List<SearchSuggestion>,
    isLoading: Boolean,
    onSuggestionClick: (SearchSuggestion) -> Unit,
    onSuggestionFill: (SearchSuggestion) -> Unit,
    modifier: Modifier = Modifier,
) {
    val querySuggestions = suggestions.filterIsInstance<SearchSuggestion.Query>()

    Box(modifier = modifier.fillMaxSize()) {
        LazyColumn(modifier = Modifier.fillMaxSize()) {
            items(
                items = querySuggestions,
                key = { it.id },
            ) { suggestion ->
                QuerySuggestionRow(
                    suggestion = suggestion,
                    onClick = { onSuggestionClick(suggestion) },
                    onFillQuery = { onSuggestionFill(suggestion) },
                )
            }
        }
        if (isLoading && querySuggestions.isEmpty()) {
            CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
        }
    }
}

@Composable
private fun QuerySuggestionRow(
    suggestion: SearchSuggestion.Query,
    onClick: () -> Unit,
    onFillQuery: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = if (suggestion.isFromHistory) Icons.Default.History else Icons.Default.Search,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(22.dp),
        )
        Text(
            text = suggestion.text,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = 12.dp),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        IconButton(
            onClick = onFillQuery,
            modifier = Modifier.size(36.dp),
        ) {
            Icon(
                imageVector = Icons.Default.NorthWest,
                contentDescription = stringResource(R.string.search_fill_query),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(20.dp),
            )
        }
    }
}
