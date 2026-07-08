package com.ytlite.player.ui.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.ViewList
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.ytlite.player.R
import com.ytlite.player.data.model.LibrarySort
import com.ytlite.player.data.model.LibraryViewMode

@Composable
fun LibraryControlBar(
    sort: LibrarySort,
    viewMode: LibraryViewMode,
    onSortClick: () -> Unit,
    onToggleViewMode: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = when (sort) {
                LibrarySort.RECENT_ACTIVITY -> stringResource(R.string.library_sort_recent_activity)
                LibrarySort.RECENTLY_SAVED -> stringResource(R.string.library_sort_recently_saved)
            },
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.clickable(onClick = onSortClick),
        )
        IconButton(onClick = onToggleViewMode) {
            Icon(
                imageVector = if (viewMode == LibraryViewMode.LIST) {
                    Icons.Default.GridView
                } else {
                    Icons.Default.ViewList
                },
                contentDescription = stringResource(R.string.library_toggle_view_mode),
            )
        }
    }
}
