package com.ytlite.player.ui.trackaction

import android.app.Application
import android.widget.Toast
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.MusicNote
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material.icons.outlined.Videocam
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.ytlite.player.R
import com.ytlite.player.data.model.StreamFormat
import java.util.Locale
import kotlin.math.max

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DownloadFormatBottomSheet(
    videoId: String,
    onDismiss: () -> Unit,
) {
    val application = LocalContext.current.applicationContext as Application
    val androidContext = LocalContext.current
    val viewModel: DownloadFormatViewModel = viewModel(
        key = "download-formats-$videoId",
        factory = DownloadFormatViewModel.factory(application, videoId),
    )
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 20.dp),
        ) {
            Text(
                text = stringResource(R.string.track_download_as_title),
                style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold),
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
            )

            when {
                uiState.isLoading -> {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 220.dp)
                            .padding(24.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                    }
                }
                uiState.errorMessage != null -> {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 20.dp, vertical = 24.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text(
                            text = when (uiState.errorMessage) {
                                "empty" -> stringResource(R.string.player_format_unavailable)
                                else -> stringResource(R.string.track_download_formats_error)
                            },
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        if (uiState.errorMessage != "empty") {
                            TextButton(onClick = { viewModel.loadFormats() }) {
                                Text(stringResource(R.string.home_retry))
                            }
                        }
                    }
                }
                else -> {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(max = 460.dp)
                            .verticalScroll(rememberScrollState())
                            .padding(horizontal = 8.dp),
                    ) {
                        if (uiState.musicOptions.isNotEmpty()) {
                            SectionHeader(text = stringResource(R.string.track_download_section_music))
                            uiState.musicOptions.forEach { option ->
                                DownloadOptionRow(
                                    option = option,
                                    selected = option.format.itag == uiState.selectedItag,
                                    onClick = { viewModel.selectItag(option.format.itag) },
                                )
                            }
                        }
                        if (uiState.videoOptions.isNotEmpty()) {
                            SectionHeader(text = stringResource(R.string.track_download_section_video))
                            uiState.videoOptions.forEach { option ->
                                DownloadOptionRow(
                                    option = option,
                                    selected = option.format.itag == uiState.selectedItag,
                                    onClick = { viewModel.selectItag(option.format.itag) },
                                )
                            }
                        }

                        if (uiState.moreOptions.isNotEmpty()) {
                            HorizontalDivider(
                                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                            )
                            MoreFormatsRow(
                                expanded = uiState.showAllFormats,
                                count = uiState.moreOptions.size,
                                onClick = viewModel::toggleShowAllFormats,
                            )
                            if (uiState.showAllFormats) {
                                uiState.moreOptions.forEach { option ->
                                    DownloadOptionRow(
                                        option = option,
                                        selected = option.format.itag == uiState.selectedItag,
                                        onClick = { viewModel.selectItag(option.format.itag) },
                                    )
                                }
                            }
                        }

                        Spacer(modifier = Modifier.height(8.dp))
                    }

                    Button(
                        onClick = {
                            if (uiState.selectedItag == null) {
                                Toast.makeText(
                                    androidContext,
                                    androidContext.getString(R.string.track_download_select_hint),
                                    Toast.LENGTH_SHORT,
                                ).show()
                                return@Button
                            }
                            viewModel.enqueueSelected { result ->
                                val message = when (result) {
                                    is com.ytlite.player.download.EnqueueResult.Started ->
                                        androidContext.getString(R.string.download_added)
                                    is com.ytlite.player.download.EnqueueResult.AlreadyDownloaded ->
                                        androidContext.getString(R.string.download_already_done)
                                    is com.ytlite.player.download.EnqueueResult.AlreadyRunning ->
                                        androidContext.getString(R.string.download_already_running)
                                    is com.ytlite.player.download.EnqueueResult.Error -> when (result.message) {
                                        "wifi_only" -> androidContext.getString(R.string.download_wifi_only_blocked)
                                        "select_format" -> androidContext.getString(R.string.track_download_select_hint)
                                        else -> androidContext.getString(R.string.download_enqueue_failed)
                                    }
                                }
                                Toast.makeText(androidContext, message, Toast.LENGTH_SHORT).show()
                                if (result is com.ytlite.player.download.EnqueueResult.Started ||
                                    result is com.ytlite.player.download.EnqueueResult.AlreadyDownloaded ||
                                    result is com.ytlite.player.download.EnqueueResult.AlreadyRunning
                                ) {
                                    onDismiss()
                                }
                            }
                        },
                        enabled = uiState.selectedItag != null && !uiState.isEnqueueing,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 20.dp, vertical = 8.dp)
                            .height(52.dp),
                        shape = RoundedCornerShape(50),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.primary,
                            contentColor = MaterialTheme.colorScheme.onPrimary,
                            disabledContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                            disabledContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                        ),
                    ) {
                        Text(
                            text = stringResource(R.string.player_download),
                            style = MaterialTheme.typography.titleMedium.copy(
                                fontWeight = FontWeight.SemiBold,
                            ),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun SectionHeader(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
    )
}

@Composable
private fun MoreFormatsRow(
    expanded: Boolean,
    count: Int,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = stringResource(R.string.track_download_more_formats),
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier.weight(1f),
        )
        Text(
            text = if (expanded) {
                stringResource(R.string.track_download_more_hide)
            } else {
                stringResource(R.string.track_download_more_all)
            },
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (!expanded) {
            Text(
                text = " ($count)",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Icon(
            imageVector = Icons.AutoMirrored.Outlined.KeyboardArrowRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(22.dp),
        )
    }
}

@Composable
private fun DownloadOptionRow(
    option: DownloadFormatOption,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val label = optionLabel(option)
    val sizeLabel = formatContentLength(option.format.contentLengthBytes)
    val icon = when (option.kind) {
        DownloadFormatKind.Music -> Icons.Outlined.MusicNote
        DownloadFormatKind.Video -> Icons.Outlined.Videocam
    }
    val contentColor = MaterialTheme.colorScheme.onSurface
    val muted = MaterialTheme.colorScheme.onSurfaceVariant

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = muted,
            modifier = Modifier.size(24.dp),
        )
        Text(
            text = label,
            style = MaterialTheme.typography.bodyLarge,
            color = contentColor,
            modifier = Modifier.weight(1f),
        )
        if (sizeLabel != null) {
            Text(
                text = sizeLabel,
                style = MaterialTheme.typography.bodyMedium,
                color = muted,
            )
        }
        Icon(
            imageVector = if (selected) {
                Icons.Filled.CheckCircle
            } else {
                Icons.Outlined.RadioButtonUnchecked
            },
            contentDescription = null,
            tint = if (selected) {
                MaterialTheme.colorScheme.primary
            } else {
                muted
            },
            modifier = Modifier.size(26.dp),
        )
    }
}

@Composable
private fun optionLabel(option: DownloadFormatOption): String {
    return when (option.labelKey) {
        DownloadFormatLabel.MusicFast -> stringResource(R.string.track_download_music_fast)
        DownloadFormatLabel.MusicClassic -> stringResource(R.string.track_download_music_classic)
        DownloadFormatLabel.MusicHigh -> stringResource(R.string.track_download_music_high)
        DownloadFormatLabel.VideoFast360 -> stringResource(R.string.track_download_video_fast_360)
        DownloadFormatLabel.VideoHigh720 -> stringResource(R.string.track_download_video_high_720)
        DownloadFormatLabel.VideoBest1080 -> stringResource(R.string.track_download_video_best_1080)
        DownloadFormatLabel.Generic -> genericFormatLabel(option.format)
    }
}

@Composable
private fun genericFormatLabel(format: StreamFormat): String {
    return when {
        format.hasVideo && format.height > 0 -> {
            stringResource(R.string.track_download_video_generic, format.height)
        }
        format.hasAudio && !format.hasVideo -> {
            stringResource(R.string.track_download_music_generic, format.itag)
        }
        else -> stringResource(R.string.player_format_itag, format.itag)
    }
}

private fun formatContentLength(bytes: Long): String? {
    if (bytes <= 0L) return null
    val mb = bytes / (1024.0 * 1024.0)
    return if (mb >= 10) {
        String.format(Locale.US, "%.0fMB", mb)
    } else {
        String.format(Locale.US, "%.1fMB", max(0.1, mb))
    }
}
