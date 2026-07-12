package com.ytlite.player.ui.library

import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DragHandle
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.outlined.PushPin
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import com.ytlite.player.R
import com.ytlite.player.data.model.DataSource
import com.ytlite.player.data.model.LibraryItem
import com.ytlite.player.ui.playback.clickableNoRipple

@Composable
fun LibraryRowItem(
    item: LibraryItem,
    onClick: () -> Unit,
    onMoreClick: (() -> Unit)? = null,
    reorderMode: Boolean = false,
    index: Int = 0,
    itemCount: Int = 0,
    playlists: List<LibraryItem.Playlist> = emptyList(),
    onDrag: ((from: Int, to: Int) -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    val itemHeightPx = with(LocalDensity.current) { 76.dp.toPx() }
    val dragEnabled = reorderMode && item is LibraryItem.Playlist && onDrag != null

    Row(
        modifier = modifier
            .fillMaxWidth()
            .then(
                if (dragEnabled) {
                    Modifier.pointerInput(item.id, itemCount, playlists) {
                        var dragFrom = -1
                        var dragOffsetY = 0f
                        detectDragGesturesAfterLongPress(
                            onDragStart = {
                                dragFrom = index
                                dragOffsetY = 0f
                            },
                            onDrag = { change, dragAmount ->
                                change.consume()
                                dragOffsetY += dragAmount.y
                                val delta = (dragOffsetY / itemHeightPx).toInt()
                                val dragTo = (dragFrom + delta).coerceIn(0, itemCount - 1)
                                if (
                                    dragFrom >= 0 &&
                                    dragTo != dragFrom &&
                                    samePinGroup(playlists, dragFrom, dragTo)
                                ) {
                                    onDrag?.invoke(dragFrom, dragTo)
                                    dragFrom = dragTo
                                    dragOffsetY = 0f
                                }
                            },
                            onDragEnd = {
                                dragFrom = -1
                                dragOffsetY = 0f
                            },
                            onDragCancel = {
                                dragFrom = -1
                                dragOffsetY = 0f
                            },
                        )
                    }
                } else {
                    Modifier
                },
            )
            .then(
                if (dragEnabled) {
                    Modifier.clickableNoRipple(onClick)
                } else {
                    Modifier.clickable(onClick = onClick)
                },
            )
            .padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (dragEnabled) {
            Icon(
                imageVector = Icons.Filled.DragHandle,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(24.dp),
            )
        }
        Box {
            LibraryPlaylistThumbnail(
                item = item,
                modifier = Modifier
                    .size(56.dp)
                    .clip(RoundedCornerShape(8.dp)),
                iconSize = 28.dp,
            )
            if (item.source == DataSource.YOUTUBE) {
                YoutubeBadge(modifier = Modifier.align(Alignment.BottomEnd))
            }
        }
        Column(modifier = Modifier.weight(1f)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    text = item.title,
                    style = MaterialTheme.typography.bodyLarge,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false),
                )
                if (item is LibraryItem.Playlist && item.isPinned) {
                    Icon(
                        imageVector = Icons.Outlined.PushPin,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            if (item.subtitle.isNotBlank()) {
                Text(
                    text = item.subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        if (onMoreClick != null && !reorderMode) {
            IconButton(onClick = onMoreClick) {
                Icon(
                    imageVector = Icons.Default.MoreVert,
                    contentDescription = stringResource(R.string.library_song_more),
                )
            }
        }
    }
}

private fun samePinGroup(
    playlists: List<LibraryItem.Playlist>,
    fromIndex: Int,
    toIndex: Int,
): Boolean {
    val from = playlists.getOrNull(fromIndex) ?: return false
    val to = playlists.getOrNull(toIndex) ?: return false
    return from.isPinned == to.isPinned
}
