package com.ytlite.player.ui.library

import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import com.ytlite.player.data.model.LibraryItem
import kotlin.math.roundToInt

@Composable
fun ReorderablePlaylistList(
    playlists: List<LibraryItem.Playlist>,
    onItemClick: (LibraryItem.Playlist) -> Unit,
    onOrderCommitted: (List<LibraryItem.Playlist>) -> Unit,
    modifier: Modifier = Modifier,
) {
    var localPinned by remember { mutableStateOf(playlists.filter { it.isPinned }) }
    var localUnpinned by remember { mutableStateOf(playlists.filter { !it.isPinned }) }
    var isDragging by remember { mutableStateOf(false) }
    var pendingCommitIds by remember { mutableStateOf<List<String>?>(null) }

    LaunchedEffect(playlists, isDragging) {
        if (isDragging) return@LaunchedEffect
        val remoteIds = playlists.map { it.id }
        when {
            pendingCommitIds != null -> {
                if (remoteIds == pendingCommitIds) {
                    pendingCommitIds = null
                    localPinned = playlists.filter { it.isPinned }
                    localUnpinned = playlists.filter { !it.isPinned }
                }
            }
            else -> {
                localPinned = playlists.filter { it.isPinned }
                localUnpinned = playlists.filter { !it.isPinned }
            }
        }
    }

    val commitIfChanged: (List<LibraryItem.Playlist>, List<LibraryItem.Playlist>, List<String>) -> Unit =
        { pinned, unpinned, startIds ->
            val merged = pinned + unpinned
            val mergedIds = merged.map { it.id }
            if (mergedIds != startIds) {
                pendingCommitIds = mergedIds
                onOrderCommitted(merged)
            }
        }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(bottom = 88.dp),
    ) {
        if (localPinned.isNotEmpty()) {
            reorderablePlaylistGroup(
                items = localPinned,
                isDragging = isDragging,
                onDraggingChanged = { isDragging = it },
                onItemClick = onItemClick,
                onOrderChanged = { localPinned = it },
                onOrderCommitted = { pinned, startIds ->
                    commitIfChanged(pinned, localUnpinned, startIds)
                },
            )
        }
        if (localUnpinned.isNotEmpty()) {
            reorderablePlaylistGroup(
                items = localUnpinned,
                isDragging = isDragging,
                onDraggingChanged = { isDragging = it },
                onItemClick = onItemClick,
                onOrderChanged = { localUnpinned = it },
                onOrderCommitted = { unpinned, startIds ->
                    commitIfChanged(localPinned, unpinned, startIds)
                },
            )
        }
    }
}

private fun androidx.compose.foundation.lazy.LazyListScope.reorderablePlaylistGroup(
    items: List<LibraryItem.Playlist>,
    isDragging: Boolean,
    onDraggingChanged: (Boolean) -> Unit,
    onItemClick: (LibraryItem.Playlist) -> Unit,
    onOrderChanged: (List<LibraryItem.Playlist>) -> Unit,
    onOrderCommitted: (List<LibraryItem.Playlist>, List<String>) -> Unit,
) {
    itemsIndexed(items, key = { _, item -> item.id }) { index, item ->
        ReorderablePlaylistRow(
            item = item,
            index = index,
            itemCount = items.size,
            items = items,
            isDragging = isDragging,
            onDraggingChanged = onDraggingChanged,
            onItemClick = onItemClick,
            onOrderChanged = onOrderChanged,
            onOrderCommitted = onOrderCommitted,
        )
    }
}

@Composable
private fun ReorderablePlaylistRow(
    item: LibraryItem.Playlist,
    index: Int,
    itemCount: Int,
    items: List<LibraryItem.Playlist>,
    isDragging: Boolean,
    onDraggingChanged: (Boolean) -> Unit,
    onItemClick: (LibraryItem.Playlist) -> Unit,
    onOrderChanged: (List<LibraryItem.Playlist>) -> Unit,
    onOrderCommitted: (List<LibraryItem.Playlist>, List<String>) -> Unit,
) {
    var draggingId by remember { mutableStateOf<String?>(null) }
    var dragOffsetY by remember { mutableFloatStateOf(0f) }
    var orderAtDragStart by remember { mutableStateOf(items.map { it.id }) }
    val currentItems by rememberUpdatedState(items)

    val itemHeightPx = with(LocalDensity.current) { 76.dp.toPx() }
    val draggingIndex = draggingId?.let { id -> currentItems.indexOfFirst { it.id == id } } ?: -1
    val clampedDragOffsetY = if (draggingIndex >= 0) {
        clampDragOffsetY(dragOffsetY, draggingIndex, currentItems.size, itemHeightPx)
    } else {
        0f
    }
    val itemTranslationY = playlistItemDragOffset(
        index = index,
        draggingIndex = draggingIndex,
        dragOffsetY = clampedDragOffsetY,
        itemHeightPx = itemHeightPx,
        itemCount = currentItems.size,
    )
    val isActiveDragItem = index == draggingIndex

    LibraryRowItem(
        item = item,
        onClick = { onItemClick(item) },
        onMoreClick = null,
        showDragHandle = true,
        modifier = Modifier
            .zIndex(if (isActiveDragItem) 1f else 0f)
            .graphicsLayer {
                translationY = itemTranslationY
                if (isActiveDragItem) {
                    shadowElevation = 8.dp.toPx()
                    alpha = 0.98f
                }
            },
        dragHandleModifier = Modifier
            .padding(horizontal = 4.dp, vertical = 8.dp)
            .pointerInput(item.id, itemCount) {
                detectDragGestures(
                    onDragStart = {
                        onDraggingChanged(true)
                        draggingId = item.id
                        dragOffsetY = 0f
                        orderAtDragStart = currentItems.map { it.id }
                    },
                    onDrag = { change, dragAmount ->
                        change.consume()
                        val list = currentItems
                        val currentIndex = list.indexOfFirst { it.id == draggingId }
                        if (currentIndex < 0) return@detectDragGestures

                        dragOffsetY = clampDragOffsetY(
                            dragOffsetY + dragAmount.y,
                            currentIndex,
                            list.size,
                            itemHeightPx,
                        )
                        val targetIndex = (currentIndex + (dragOffsetY / itemHeightPx).roundToInt())
                            .coerceIn(0, list.size - 1)
                        if (targetIndex != currentIndex) {
                            val reordered = list.toMutableList().apply {
                                val moved = removeAt(currentIndex)
                                add(targetIndex, moved)
                            }
                            onOrderChanged(reordered)
                            dragOffsetY -= (targetIndex - currentIndex) * itemHeightPx
                        }
                    },
                    onDragEnd = {
                        if (draggingId != null) {
                            onOrderCommitted(currentItems, orderAtDragStart)
                        }
                        onDraggingChanged(false)
                        draggingId = null
                        dragOffsetY = 0f
                    },
                    onDragCancel = {
                        onDraggingChanged(false)
                        draggingId = null
                        dragOffsetY = 0f
                    },
                )
            },
    )
}

internal fun clampDragOffsetY(
    dragOffsetY: Float,
    draggingIndex: Int,
    itemCount: Int,
    itemHeightPx: Float,
): Float {
    if (itemCount <= 1) return 0f
    val maxDown = (itemCount - 1 - draggingIndex) * itemHeightPx
    val maxUp = draggingIndex * itemHeightPx
    return dragOffsetY.coerceIn(-maxUp, maxDown)
}

internal fun playlistItemDragOffset(
    index: Int,
    draggingIndex: Int,
    dragOffsetY: Float,
    itemHeightPx: Float,
    itemCount: Int,
): Float {
    if (draggingIndex < 0 || itemCount <= 0) return 0f

    val targetIndex = (draggingIndex + (dragOffsetY / itemHeightPx).roundToInt())
        .coerceIn(0, itemCount - 1)

    return when {
        index == draggingIndex -> dragOffsetY
        targetIndex > draggingIndex && index in (draggingIndex + 1)..targetIndex -> -itemHeightPx
        targetIndex < draggingIndex && index in targetIndex until draggingIndex -> itemHeightPx
        else -> 0f
    }
}
