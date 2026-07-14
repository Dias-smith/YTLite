package com.ytlite.player.ui.library

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
    selectedFilter: LibraryFilterChip,
    onChipSelected: (LibraryFilterChip) -> Unit,
    isPlaylistReorderMode: Boolean = false,
    onExitPlaylistReorder: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(start = 8.dp, end = 4.dp, top = 4.dp, bottom = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            modifier = Modifier
                .weight(1f)
                .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            visibleChips.forEach { chip ->
                FilterChip(
                    selected = selectedFilter == chip,
                    onClick = { onChipSelected(chip) },
                    label = { Text(text = chipLabel(chip)) },
                    enabled = !isPlaylistReorderMode || chip == LibraryFilterChip.PLAYLISTS,
                )
            }
        }
        if (isPlaylistReorderMode) {
            TextButton(onClick = onExitPlaylistReorder) {
                Text(text = stringResource(R.string.library_playlist_reorder_done))
            }
        }
    }
}

@Composable
private fun chipLabel(chip: LibraryFilterChip): String = when (chip) {
    LibraryFilterChip.PLAYLISTS -> stringResource(R.string.library_chip_playlists)
    LibraryFilterChip.SONGS -> stringResource(R.string.library_chip_songs)
    LibraryFilterChip.CHANNELS -> stringResource(R.string.library_chip_channels)
    LibraryFilterChip.ALBUMS -> stringResource(R.string.library_chip_albums)
    LibraryFilterChip.YOUTUBE -> stringResource(R.string.library_chip_youtube)
}
