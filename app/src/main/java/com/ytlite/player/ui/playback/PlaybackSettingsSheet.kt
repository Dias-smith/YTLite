package com.ytlite.player.ui.playback

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.ytlite.player.R
import com.ytlite.player.data.model.StreamFormat

private val SPEED_OPTIONS = listOf(0.25f, 0.5f, 0.75f, 1f, 1.25f, 1.5f, 1.75f, 2f)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlaybackSettingsSheet(
    visible: Boolean,
    currentSpeed: Float,
    formats: List<StreamFormat>,
    selectedItag: Int?,
    onDismiss: () -> Unit,
    onSpeedSelected: (Float) -> Unit,
    onFormatSelected: (StreamFormat) -> Unit,
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
                text = stringResource(R.string.player_settings),
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
            Text(
                text = stringResource(R.string.player_playback_speed),
                style = MaterialTheme.typography.labelLarge,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
            SPEED_OPTIONS.forEach { speed ->
                val label = if (speed == 1f) {
                    stringResource(R.string.player_speed_normal)
                } else {
                    "${speed}x"
                }
                Text(
                    text = label,
                    style = MaterialTheme.typography.bodyLarge,
                    color = if (speed == currentSpeed) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurface
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onSpeedSelected(speed) }
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                )
            }
            if (formats.isNotEmpty()) {
                HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
                Text(
                    text = stringResource(R.string.player_quality),
                    style = MaterialTheme.typography.labelLarge,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
                formats.forEach { format ->
                    val resolution = if (format.height > 0) "${format.height}p" else format.mimeType
                    Text(
                        text = resolution,
                        style = MaterialTheme.typography.bodyLarge,
                        color = if (format.itag == selectedItag) {
                            MaterialTheme.colorScheme.primary
                        } else {
                            MaterialTheme.colorScheme.onSurface
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onFormatSelected(format) }
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                    )
                }
            }
        }
    }
}
