package com.ytlite.player.ui.playback

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
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
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.ytlite.player.R
import com.ytlite.player.playback.QueueItem

@Composable
fun QueueListItem(
    item: QueueItem,
    isCurrent: Boolean,
    onClick: () -> Unit,
    onMoreClick: () -> Unit,
    onDrag: (fromIndex: Int, toIndex: Int) -> Unit,
    index: Int,
    itemCount: Int,
    modifier: Modifier = Modifier,
) {
    val itemHeightPx = with(LocalDensity.current) { 72.dp.toPx() }
    val background = when {
        isCurrent -> Color(0xFF1F1F1F)
        else -> Color.Transparent
    }

    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(background)
            .clickableNoRipple(onClick)
            .pointerInput(item.videoId, itemCount) {
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
                        if (dragFrom >= 0 && dragTo != dragFrom) {
                            onDrag(dragFrom, dragTo)
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
            .padding(horizontal = 8.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = Icons.Filled.DragHandle,
            contentDescription = null,
            tint = Color(0xFF666666),
            modifier = Modifier.padding(end = 4.dp),
        )
        Box(modifier = Modifier.size(48.dp)) {
            AsyncImage(
                model = item.thumbnailUrl,
                contentDescription = item.title,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .size(48.dp)
                    .clip(RoundedCornerShape(4.dp)),
            )
            item.durationText?.takeIf { it.isNotBlank() }?.let { duration ->
                Text(
                    text = duration,
                    color = Color.White,
                    style = MaterialTheme.typography.labelSmall,
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .background(Color(0xCC000000), RoundedCornerShape(2.dp))
                        .padding(horizontal = 3.dp, vertical = 1.dp),
                )
            }
        }
        Column(
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = 12.dp),
        ) {
            Text(
                text = item.title,
                style = MaterialTheme.typography.bodyMedium,
                color = if (isCurrent) Color.White else Color(0xFFDDDDDD),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = item.subtitleLine(),
                style = MaterialTheme.typography.bodySmall,
                color = Color(0xFF888888),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        IconButton(onClick = onMoreClick) {
            Icon(
                imageVector = Icons.Filled.MoreVert,
                contentDescription = stringResource(R.string.player_item_menu),
                tint = Color(0xFF888888),
            )
        }
    }
}
