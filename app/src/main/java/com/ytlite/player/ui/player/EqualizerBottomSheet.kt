package com.ytlite.player.ui.player

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Slider
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SheetState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.ytlite.player.R
import com.ytlite.player.playback.PlaybackEqualizerCatalog
import com.ytlite.player.playback.PlaybackEqualizerPreset
import com.ytlite.player.playback.PlaybackEqualizerState
import com.ytlite.player.playback.PlaybackEqualizerStore

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EqualizerBottomSheet(
    state: PlaybackEqualizerState,
    sheetState: SheetState,
    onDismiss: () -> Unit,
    onEnabledChange: (Boolean) -> Unit,
    onPresetSelect: (String) -> Unit,
    onCustomBandChange: (Int, Float) -> Unit,
    onResetCustom: () -> Unit,
    onVolumeBoostChange: (Float) -> Unit,
) {
    val context = LocalContext.current
    val frequencies = PlaybackEqualizerCatalog.bandFrequencies(context)
    val presets = PlaybackEqualizerCatalog.presets(context)
    val controlsEnabled = state.streamEligible
    val bandsEnabled = controlsEnabled && state.isEnabled
    val activeGains = state.activeGainsDb

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(bottom = 24.dp),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 20.dp, end = 12.dp, top = 8.dp, bottom = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = stringResource(R.string.equalizer_title),
                    style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold),
                )
                Switch(
                    checked = state.isEnabled,
                    onCheckedChange = onEnabledChange,
                    enabled = controlsEnabled,
                )
            }

            if (!controlsEnabled) {
                Text(
                    text = stringResource(R.string.equalizer_live_unavailable),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 4.dp),
                )
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

            Text(
                text = stringResource(R.string.equalizer_presets),
                style = MaterialTheme.typography.titleSmall,
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 4.dp),
            )
            EqualizerPresetChipRow(
                presets = presets,
                selectedPresetId = state.selectedPresetId,
                enabled = controlsEnabled,
                onPresetSelect = onPresetSelect,
                modifier = Modifier.padding(vertical = 8.dp),
            )

            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState())
                    .padding(horizontal = 12.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.Bottom,
            ) {
                frequencies.forEachIndexed { index, frequencyHz ->
                    EqualizerBandSlider(
                        frequencyHz = frequencyHz,
                        gainDb = activeGains[index],
                        enabled = bandsEnabled,
                        onGainChange = { onCustomBandChange(index, it) },
                    )
                }
            }

            TextButton(
                onClick = onResetCustom,
                enabled = controlsEnabled,
                modifier = Modifier.padding(horizontal = 12.dp),
            ) {
                Text(text = stringResource(R.string.equalizer_reset_custom))
            }

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp, vertical = 8.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = stringResource(R.string.equalizer_volume_boost),
                        style = MaterialTheme.typography.titleSmall,
                    )
                    Text(
                        text = stringResource(R.string.equalizer_volume_boost_value, state.volumeBoostPercent.toInt()),
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Slider(
                    value = state.volumeBoostPercent,
                    onValueChange = onVolumeBoostChange,
                    valueRange = PlaybackEqualizerCatalog.MIN_VOLUME_BOOST_PERCENT..PlaybackEqualizerCatalog.MAX_VOLUME_BOOST_PERCENT,
                    steps = 79,
                    enabled = controlsEnabled,
                )
            }

            Text(
                text = stringResource(R.string.equalizer_airplay_notice),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
            )
        }
    }
}

@Composable
private fun EqualizerPresetChipRow(
    presets: List<PlaybackEqualizerPreset>,
    selectedPresetId: String,
    enabled: Boolean,
    onPresetSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val highlight = MaterialTheme.colorScheme.primary
    val listState = rememberLazyListState()
    val selectedIndex = presets.indexOfFirst { it.id == selectedPresetId }
    LaunchedEffect(selectedPresetId, presets) {
        if (selectedIndex >= 0) {
            listState.animateScrollToItem(selectedIndex)
        }
    }
    LazyRow(
        state = listState,
        modifier = modifier.fillMaxWidth(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 20.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(presets, key = { it.id }) { preset ->
            val selected = selectedPresetId == preset.id
            FilterChip(
                selected = selected,
                onClick = { onPresetSelect(preset.id) },
                enabled = enabled,
                label = {
                    Text(
                        text = stringResource(PlaybackEqualizerCatalog.presetLabelRes(preset)),
                        style = MaterialTheme.typography.labelLarge,
                        maxLines = 1,
                        overflow = TextOverflow.Clip,
                        softWrap = false,
                    )
                },
                shape = RoundedCornerShape(50),
                border = null,
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = highlight,
                    selectedLabelColor = MaterialTheme.colorScheme.onPrimary,
                    containerColor = MaterialTheme.colorScheme.surfaceVariant,
                    labelColor = MaterialTheme.colorScheme.onSurface,
                ),
            )
        }
    }
}

@Composable
private fun EqualizerBandSlider(
    frequencyHz: Int,
    gainDb: Float,
    enabled: Boolean,
    onGainChange: (Float) -> Unit,
) {
    val label = if (frequencyHz >= 1000) "${frequencyHz / 1000}k" else "$frequencyHz"
    val trackHeight = 320.dp
    val thumbSize = 14.dp
    val trackWidth = 3.dp
    val accent = MaterialTheme.colorScheme.primary
    val inactive = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.22f)
    val thumbColor = Color(0xFFD1D1D1)
    val density = LocalDensity.current
    val thumbRadiusPx = with(density) { thumbSize.toPx() / 2f }
    val trackWidthPx = with(density) { trackWidth.toPx() }

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.width(28.dp),
    ) {
        Text(
            text = String.format("%+.0f", gainDb),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        BoxWithConstraints(
            modifier = Modifier
                .width(28.dp)
                .height(trackHeight)
                .then(
                    if (enabled) {
                        Modifier.pointerInput(Unit) {
                            detectDragGestures(
                                onDragStart = { offset ->
                                    onGainChange(
                                        gainDbFromY(
                                            y = offset.y,
                                            heightPx = size.height.toFloat(),
                                            thumbRadiusPx = thumbRadiusPx,
                                        ),
                                    )
                                },
                                onDrag = { change, _ ->
                                    change.consume()
                                    onGainChange(
                                        gainDbFromY(
                                            y = change.position.y,
                                            heightPx = size.height.toFloat(),
                                            thumbRadiusPx = thumbRadiusPx,
                                        ),
                                    )
                                },
                            )
                        }
                    } else {
                        Modifier
                    },
                ),
        ) {
            val heightPx = constraints.maxHeight.toFloat()
            val thumbY = thumbCenterY(
                gainDb = gainDb,
                heightPx = heightPx,
                thumbRadiusPx = thumbRadiusPx,
            )
            Canvas(modifier = Modifier.fillMaxSize()) {
                val centerX = size.width / 2f
                drawLine(
                    color = inactive,
                    start = Offset(centerX, 0f),
                    end = Offset(centerX, thumbY),
                    strokeWidth = trackWidthPx,
                    cap = StrokeCap.Round,
                )
                drawLine(
                    color = accent,
                    start = Offset(centerX, thumbY),
                    end = Offset(centerX, size.height),
                    strokeWidth = trackWidthPx,
                    cap = StrokeCap.Round,
                )
                drawCircle(
                    color = thumbColor,
                    radius = thumbRadiusPx,
                    center = Offset(centerX, thumbY),
                )
                drawCircle(
                    color = Color.White.copy(alpha = 0.35f),
                    radius = thumbRadiusPx,
                    center = Offset(centerX, thumbY),
                    style = androidx.compose.ui.graphics.drawscope.Stroke(width = 0.5f),
                )
            }
        }
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

private fun thumbCenterY(gainDb: Float, heightPx: Float, thumbRadiusPx: Float): Float {
    val travel = (heightPx - thumbRadiusPx * 2f).coerceAtLeast(1f)
    val normalized = normalizedGain(gainDb)
    return (1f - normalized) * travel + thumbRadiusPx
}

private fun normalizedGain(gainDb: Float): Float {
    val range = PlaybackEqualizerCatalog.MAX_GAIN_DB - PlaybackEqualizerCatalog.MIN_GAIN_DB
    if (range <= 0f) return 0.5f
    return ((gainDb - PlaybackEqualizerCatalog.MIN_GAIN_DB) / range).coerceIn(0f, 1f)
}

private fun gainDbFromY(y: Float, heightPx: Float, thumbRadiusPx: Float): Float {
    val travel = (heightPx - thumbRadiusPx * 2f).coerceAtLeast(1f)
    val clampedY = y.coerceIn(thumbRadiusPx, heightPx - thumbRadiusPx)
    val normalized = 1f - ((clampedY - thumbRadiusPx) / travel)
    val range = PlaybackEqualizerCatalog.MAX_GAIN_DB - PlaybackEqualizerCatalog.MIN_GAIN_DB
    val raw = normalized * range + PlaybackEqualizerCatalog.MIN_GAIN_DB
    return raw.coerceIn(PlaybackEqualizerCatalog.MIN_GAIN_DB, PlaybackEqualizerCatalog.MAX_GAIN_DB)
}

@Composable
fun rememberPlaybackEqualizerStore(): PlaybackEqualizerStore {
    val context = LocalContext.current
    return androidx.compose.runtime.remember {
        PlaybackEqualizerStore.getInstance(context)
    }
}
