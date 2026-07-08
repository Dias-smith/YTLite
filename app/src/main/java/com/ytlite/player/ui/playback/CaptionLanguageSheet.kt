package com.ytlite.player.ui.playback

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.ytlite.player.R
import com.ytlite.player.data.model.CaptionTrack

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CaptionLanguageSheet(
    visible: Boolean,
    tracks: List<CaptionTrack>,
    selected: CaptionTrack?,
    onDismiss: () -> Unit,
    onTrackSelected: (CaptionTrack) -> Unit,
) {
    if (!visible) return
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 24.dp),
        ) {
            Text(
                text = stringResource(R.string.player_cc),
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
            tracks.forEach { track ->
                Text(
                    text = track.displayName,
                    style = MaterialTheme.typography.bodyLarge,
                    color = if (track == selected) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurface
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onTrackSelected(track) }
                        .padding(horizontal = 16.dp, vertical = 14.dp),
                )
            }
        }
    }
}
