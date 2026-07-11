package com.ytlite.player.ui.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.ytlite.player.R
import com.ytlite.player.data.model.LibraryFilterChip

@Composable
fun LibraryEmptyState(
    filter: LibraryFilterChip,
    onFindMusic: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(
            imageVector = Icons.Default.MusicNote,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = when (filter) {
                LibraryFilterChip.SONGS -> stringResource(R.string.library_empty_songs)
                LibraryFilterChip.ALBUMS -> stringResource(R.string.library_empty_albums)
                LibraryFilterChip.YOUTUBE -> stringResource(R.string.library_playlists_youtube_empty)
                else -> stringResource(R.string.library_empty_default)
            },
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        if (filter == LibraryFilterChip.SONGS) {
            Button(onClick = onFindMusic) {
                Text(text = stringResource(R.string.library_find_music))
            }
        }
    }
}
