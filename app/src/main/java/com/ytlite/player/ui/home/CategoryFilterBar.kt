package com.ytlite.player.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp

@Composable
fun CategoryFilterBar(
    categories: List<FeedCategory>,
    selectedCategoryId: String,
    onCategorySelected: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val listState = rememberLazyListState()

    LaunchedEffect(selectedCategoryId) {
        val index = categories.indexOfFirst { it.id == selectedCategoryId }
        if (index >= 0) {
            listState.animateScrollToItem(index)
        }
    }

    LazyRow(
        state = listState,
        modifier = modifier.fillMaxWidth(),
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(
            items = categories,
            key = { it.id },
        ) { category ->
            val selected = category.id == selectedCategoryId
            val highlight = MaterialTheme.colorScheme.primary
            FilterChip(
                selected = selected,
                onClick = { onCategorySelected(category.id) },
                label = {
                    Text(
                        text = stringResource(category.labelRes),
                        style = MaterialTheme.typography.labelLarge,
                    )
                },
                shape = RoundedCornerShape(8.dp),
                border = null,
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = highlight,
                    selectedLabelColor = MaterialTheme.colorScheme.onPrimary,
                    containerColor = Color(0xFF272727),
                    labelColor = Color.White,
                ),
            )
        }
    }
}
