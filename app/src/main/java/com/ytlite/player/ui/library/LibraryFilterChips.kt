package com.ytlite.player.ui.library

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.ytlite.player.R
import com.ytlite.player.data.model.LibraryFilterChip

@Composable
fun LibraryFilterChips(
    visibleChips: List<LibraryFilterChip>,
    selectedFilter: LibraryFilterChip?,
    onChipSelected: (LibraryFilterChip) -> Unit,
    onClearFilter: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 8.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (selectedFilter != null) {
            IconButton(onClick = onClearFilter) {
                Icon(
                    imageVector = Icons.Default.Close,
                    contentDescription = stringResource(R.string.library_clear_filter),
                )
            }
        }
        visibleChips.forEach { chip ->
            FilterChip(
                selected = selectedFilter == chip,
                onClick = { onChipSelected(chip) },
                label = { Text(text = chipLabel(chip)) },
            )
        }
    }
}

@Composable
private fun chipLabel(chip: LibraryFilterChip): String = when (chip) {
    LibraryFilterChip.PLAYLISTS -> stringResource(R.string.library_chip_playlists)
    LibraryFilterChip.SONGS -> stringResource(R.string.library_chip_songs)
    LibraryFilterChip.ARTISTS -> stringResource(R.string.library_chip_artists)
    LibraryFilterChip.DOWNLOADS -> stringResource(R.string.library_chip_downloads)
    LibraryFilterChip.YOUTUBE -> stringResource(R.string.library_chip_youtube)
}
