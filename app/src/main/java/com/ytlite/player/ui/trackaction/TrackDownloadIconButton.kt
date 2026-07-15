package com.ytlite.player.ui.trackaction

import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.DownloadDone
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.ytlite.player.R

@Composable
fun TrackDownloadIconButton(
    videoId: String,
    modifier: Modifier = Modifier,
    buttonSize: Dp = 36.dp,
    tint: Color = LocalContentColor.current,
) {
    val downloadedIds = LocalDownloadedVideoIds.current
    val onDownloadClick = LocalTrackDownloadClick.current
    val isDownloaded = videoId in downloadedIds
    IconButton(
        onClick = { onDownloadClick(videoId) },
        modifier = modifier.size(buttonSize),
    ) {
        Icon(
            imageVector = if (isDownloaded) {
                Icons.Outlined.DownloadDone
            } else {
                Icons.Outlined.Download
            },
            contentDescription = stringResource(
                if (isDownloaded) {
                    R.string.download_video_already_downloaded
                } else {
                    R.string.library_action_download
                },
            ),
            tint = tint,
        )
    }
}
