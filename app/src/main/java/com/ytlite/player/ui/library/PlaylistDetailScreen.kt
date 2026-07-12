package com.ytlite.player.ui.library

import android.app.Application
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.Sort
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.DragHandle
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.ytlite.player.R
import com.ytlite.player.data.local.model.PlaylistTrackDetailRow
import com.ytlite.player.data.model.DataSource
import com.ytlite.player.data.model.PlaylistTrackSort
import com.ytlite.player.playback.PlayQueueRepository
import com.ytlite.player.playback.PlaybackManager
import com.ytlite.player.playback.QueueItem
import com.ytlite.player.ui.common.ActionMenuRow
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlaylistDetailScreen(
    playlistId: String,
    ownerKey: String,
    systemType: String? = null,
    onBack: () -> Unit,
    onVideoClick: (String) -> Unit,
    onCloneYoutubePlaylist: () -> Unit,
    onSongMoreClick: (PlaylistTrackDetailRow, String, DataSource) -> Unit,
    onPlaylistMoreClick: (com.ytlite.player.ui.playlistaction.PlaylistActionContext) -> Unit,
    onPlayPlaylist: (List<QueueItem>, Int, String) -> Unit,
    onTogglePlayPause: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val application = LocalContext.current.applicationContext as Application
    val viewModel: PlaylistDetailViewModel = viewModel(
        key = "$ownerKey:${systemType ?: playlistId}",
        factory = PlaylistDetailViewModel.factory(
            application,
            playlistId,
            ownerKey,
            systemType,
        ),
    )
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val queueState by PlayQueueRepository.state.collectAsStateWithLifecycle()
    val isPlaying by PlaybackManager.isPlaying.collectAsStateWithLifecycle()
    val playlist = uiState.playlist
    val scope = rememberCoroutineScope()

    var showSortSheet by remember { mutableStateOf(false) }
    var showEditDialog by remember { mutableStateOf(false) }
    var isTrackDragging by remember { mutableStateOf(false) }
    var localTrackOrder by remember { mutableStateOf(uiState.tracks) }
    var pendingTrackCommitIds by remember { mutableStateOf<List<String>?>(null) }
    var draggingTrackId by remember { mutableStateOf<String?>(null) }
    var trackDragOffsetY by remember { mutableFloatStateOf(0f) }
    var trackOrderAtDragStart by remember { mutableStateOf(uiState.tracks.map { it.trackId }) }

    LaunchedEffect(uiState.tracks, uiState.canReorder, isTrackDragging) {
        if (!uiState.canReorder || isTrackDragging) return@LaunchedEffect
        val remoteIds = uiState.tracks.map { it.trackId }
        when {
            pendingTrackCommitIds != null -> {
                if (remoteIds == pendingTrackCommitIds) {
                    pendingTrackCommitIds = null
                    localTrackOrder = uiState.tracks
                }
            }
            else -> localTrackOrder = uiState.tracks
        }
    }

    val resolvedPlaylistId = playlist?.playlistId
    val isThisPlaylistActive =
        resolvedPlaylistId != null &&
            queueState.sourcePlaylistId == resolvedPlaylistId &&
            queueState.items.isNotEmpty()
    val showPause = isThisPlaylistActive && isPlaying
    val itemHeightPx = with(LocalDensity.current) { 64.dp.toPx() }
    val displayedTracks = if (uiState.canReorder) localTrackOrder else uiState.tracks
    val currentTrackOrder by rememberUpdatedState(localTrackOrder)
    val latestTracks by rememberUpdatedState(uiState.tracks)
    val draggingTrackIndex =
        draggingTrackId?.let { id -> localTrackOrder.indexOfFirst { it.trackId == id } } ?: -1

    Scaffold(
        modifier = modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.player_back),
                        )
                    }
                },
                actions = {
                    if (playlist?.isYoutube() == true) {
                        IconButton(onClick = onCloneYoutubePlaylist) {
                            Icon(
                                imageVector = Icons.Default.MoreVert,
                                contentDescription = stringResource(R.string.library_clone_to_local),
                            )
                        }
                    }
                },
            )
        },
    ) { innerPadding ->
        if (playlist == null) return@Scaffold

        val statsText = formatPlaylistDetailStats(
            trackCount = uiState.trackCount,
            totalDurationSeconds = uiState.totalDurationSeconds,
        )

        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            userScrollEnabled = !isTrackDragging,
        ) {
            item(key = "header") {
                PlaylistDetailHeader(
                    playlistName = playlist.name,
                    statsText = statsText,
                    coverUrls = uiState.coverUrls,
                    isLiked = playlist.isLikedSystemPlaylist(),
                    isWatchLater = playlist.isWatchLaterSystemPlaylist(),
                    canEdit = uiState.canEdit,
                    showPause = showPause,
                    onEditClick = { showEditDialog = true },
                    onPlayPauseClick = {
                        if (isThisPlaylistActive) {
                            onTogglePlayPause()
                        } else {
                            scope.launch {
                                val items = viewModel.loadQueueItems()
                                if (items.isNotEmpty()) {
                                    onPlayPlaylist(items, 0, playlist.playlistId)
                                }
                            }
                        }
                    },
                    onMoreClick = {
                        onPlaylistMoreClick(
                            com.ytlite.player.ui.playlistaction.PlaylistActionContext.fromPlaylistEntity(
                                playlist = playlist,
                                coverUrl = uiState.coverUrls.firstOrNull(),
                                ownerKey = ownerKey,
                            ),
                        )
                    },
                )
            }

            item(key = "sort") {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { showSortSheet = true }
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Outlined.Sort,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        text = stringResource(sortLabelRes(uiState.sort)),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            itemsIndexed(
                items = displayedTracks,
                key = { _, track -> track.trackId },
            ) { index, track ->
                val isActive = uiState.canReorder && index == draggingTrackIndex
                val translation = if (isActive) {
                    clampTrackDragOffset(
                        trackDragOffsetY,
                        draggingTrackIndex,
                        localTrackOrder.size,
                        itemHeightPx,
                    )
                } else {
                    0f
                }
                PlaylistTrackRow(
                    track = track,
                    showDragHandle = uiState.canReorder,
                    onClick = {
                        scope.launch {
                            val items = viewModel.loadQueueItems()
                            val startIndex = items.indexOfFirst { it.videoId == track.trackId }
                                .coerceAtLeast(0)
                            if (items.isNotEmpty()) {
                                onPlayPlaylist(items, startIndex, playlist.playlistId)
                            } else {
                                onVideoClick(track.trackId)
                            }
                        }
                    },
                    onMoreClick = {
                        onSongMoreClick(track, playlist.playlistId, playlist.dataSource)
                    },
                    modifier = Modifier
                        .zIndex(if (isActive) 1f else 0f)
                        .graphicsLayer {
                            translationY = translation
                            if (isActive) {
                                shadowElevation = 6.dp.toPx()
                                alpha = 0.98f
                            }
                        },
                    dragHandleModifier = if (uiState.canReorder) {
                        Modifier
                            .padding(horizontal = 4.dp, vertical = 8.dp)
                            .pointerInput(track.trackId, displayedTracks.size) {
                                detectDragGestures(
                                    onDragStart = {
                                        isTrackDragging = true
                                        draggingTrackId = track.trackId
                                        trackDragOffsetY = 0f
                                        trackOrderAtDragStart = currentTrackOrder.map { it.trackId }
                                    },
                                    onDrag = { change, dragAmount ->
                                        change.consume()
                                        val list = currentTrackOrder
                                        val currentIndex = list.indexOfFirst { it.trackId == draggingTrackId }
                                        if (currentIndex < 0) return@detectDragGestures
                                        trackDragOffsetY = clampTrackDragOffset(
                                            trackDragOffsetY + dragAmount.y,
                                            currentIndex,
                                            list.size,
                                            itemHeightPx,
                                        )
                                        val targetIndex =
                                            (currentIndex + (trackDragOffsetY / itemHeightPx).roundToInt())
                                                .coerceIn(0, list.lastIndex)
                                        if (targetIndex != currentIndex) {
                                            localTrackOrder = list.toMutableList().apply {
                                                val moved = removeAt(currentIndex)
                                                add(targetIndex, moved)
                                            }
                                            trackDragOffsetY -=
                                                (targetIndex - currentIndex) * itemHeightPx
                                        }
                                    },
                                    onDragEnd = {
                                        if (
                                            draggingTrackId != null &&
                                            localTrackOrder.map { it.trackId } != trackOrderAtDragStart
                                        ) {
                                            pendingTrackCommitIds = localTrackOrder.map { it.trackId }
                                            viewModel.commitTrackOrder(
                                                localTrackOrder.map { it.trackId },
                                            )
                                        }
                                        isTrackDragging = false
                                        draggingTrackId = null
                                        trackDragOffsetY = 0f
                                    },
                                    onDragCancel = {
                                        isTrackDragging = false
                                        draggingTrackId = null
                                        trackDragOffsetY = 0f
                                        localTrackOrder = latestTracks
                                    },
                                )
                            }
                    } else {
                        Modifier
                    },
                )
            }

            item(key = "suggestions") {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 24.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        text = stringResource(R.string.playlist_suggestions_title),
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                    )
                    Text(
                        text = stringResource(R.string.playlist_suggestions_empty),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }

    if (showSortSheet && playlist != null) {
        PlaylistSortSheet(
            currentSort = uiState.sort,
            isYoutube = playlist.isYoutube(),
            onDismiss = { showSortSheet = false },
            onSelect = { sort ->
                viewModel.setSort(sort)
                showSortSheet = false
            },
        )
    }

    if (showEditDialog && playlist != null) {
        EditPlaylistDialog(
            initialName = playlist.name,
            onDismiss = { showEditDialog = false },
            onConfirm = { name ->
                viewModel.renamePlaylist(name) {
                    showEditDialog = false
                }
            },
        )
    }
}

@Composable
private fun formatPlaylistDetailStats(
    trackCount: Int,
    totalDurationSeconds: Int,
): String {
    val tracksLabel = pluralStringResource(R.plurals.playlist_detail_tracks, trackCount, trackCount)
    if (totalDurationSeconds <= 0) return tracksLabel
    val minutes = totalDurationSeconds / 60
    val seconds = totalDurationSeconds % 60
    val durationLabel = stringResource(R.string.playlist_detail_duration, minutes, seconds)
    return stringResource(R.string.playlist_detail_stats, tracksLabel, durationLabel)
}

private fun sortLabelRes(sort: PlaylistTrackSort): Int = when (sort) {
    PlaylistTrackSort.MANUAL -> R.string.playlist_sort_manual
    PlaylistTrackSort.RECENTLY_ADDED -> R.string.playlist_sort_recently_added
    PlaylistTrackSort.TITLE -> R.string.playlist_sort_title
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PlaylistSortSheet(
    currentSort: PlaylistTrackSort,
    isYoutube: Boolean,
    onDismiss: () -> Unit,
    onSelect: (PlaylistTrackSort) -> Unit,
) {
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
                text = stringResource(R.string.playlist_sort_title_header),
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
            if (!isYoutube) {
                SortOptionRow(
                    label = stringResource(R.string.playlist_sort_manual),
                    selected = currentSort == PlaylistTrackSort.MANUAL,
                    onClick = { onSelect(PlaylistTrackSort.MANUAL) },
                )
            }
            SortOptionRow(
                label = stringResource(R.string.playlist_sort_recently_added),
                selected = currentSort == PlaylistTrackSort.RECENTLY_ADDED,
                onClick = { onSelect(PlaylistTrackSort.RECENTLY_ADDED) },
            )
            SortOptionRow(
                label = stringResource(R.string.playlist_sort_title),
                selected = currentSort == PlaylistTrackSort.TITLE,
                onClick = { onSelect(PlaylistTrackSort.TITLE) },
            )
        }
    }
}

@Composable
private fun SortOptionRow(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
) {
    ActionMenuRow(
        icon = if (selected) Icons.Default.Check else Icons.AutoMirrored.Outlined.Sort,
        label = label,
        onClick = onClick,
    )
}

@Composable
private fun PlaylistDetailHeader(
    playlistName: String,
    statsText: String,
    coverUrls: List<String>,
    isLiked: Boolean,
    isWatchLater: Boolean,
    canEdit: Boolean,
    showPause: Boolean,
    onEditClick: () -> Unit,
    onPlayPauseClick: () -> Unit,
    onMoreClick: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        PlaylistCoverArt(
            coverUrls = coverUrls,
            isLiked = isLiked,
            isWatchLater = isWatchLater,
            modifier = Modifier
                .fillMaxWidth(0.55f)
                .aspectRatio(1f),
        )
        Text(
            text = playlistName,
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            text = statsText,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Row(
            horizontalArrangement = Arrangement.spacedBy(28.dp),
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(top = 8.dp),
        ) {
            if (canEdit) {
                IconButton(
                    onClick = onEditClick,
                    colors = IconButtonDefaults.iconButtonColors(
                        containerColor = MaterialTheme.colorScheme.surfaceVariant,
                    ),
                    modifier = Modifier.size(48.dp),
                ) {
                    Icon(
                        imageVector = Icons.Outlined.Edit,
                        contentDescription = stringResource(R.string.playlist_action_edit),
                    )
                }
            } else {
                Box(modifier = Modifier.size(48.dp))
            }
            FilledIconButton(
                onClick = onPlayPauseClick,
                modifier = Modifier.size(72.dp),
                shape = CircleShape,
            ) {
                Icon(
                    imageVector = if (showPause) Icons.Default.Pause else Icons.Default.PlayArrow,
                    contentDescription = stringResource(
                        if (showPause) R.string.playlist_detail_pause else R.string.library_play_all,
                    ),
                    modifier = Modifier.size(36.dp),
                )
            }
            IconButton(
                onClick = onMoreClick,
                colors = IconButtonDefaults.iconButtonColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant,
                ),
                modifier = Modifier.size(48.dp),
            ) {
                Icon(
                    imageVector = Icons.Default.MoreVert,
                    contentDescription = stringResource(R.string.library_song_more),
                )
            }
        }
    }
}

internal fun clampTrackDragOffset(
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

@Composable
private fun PlaylistCoverArt(
    coverUrls: List<String>,
    isLiked: Boolean,
    isWatchLater: Boolean,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier.clip(RoundedCornerShape(8.dp)),
        contentAlignment = Alignment.Center,
    ) {
        when {
            isLiked -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(
                            Brush.linearGradient(
                                colors = listOf(Color(0xFF4FC3F7), Color(0xFFE91E63)),
                            ),
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Default.ThumbUp,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier.size(64.dp),
                    )
                }
            }
            isWatchLater -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(MaterialTheme.colorScheme.primaryContainer),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Default.Schedule,
                        contentDescription = null,
                        modifier = Modifier.size(64.dp),
                    )
                }
            }
            coverUrls.size >= 4 -> {
                Column(modifier = Modifier.fillMaxSize()) {
                    Row(modifier = Modifier.weight(1f)) {
                        LibraryImage(coverUrls[0], null, Modifier.weight(1f).fillMaxSize())
                        LibraryImage(coverUrls[1], null, Modifier.weight(1f).fillMaxSize())
                    }
                    Row(modifier = Modifier.weight(1f)) {
                        LibraryImage(coverUrls[2], null, Modifier.weight(1f).fillMaxSize())
                        LibraryImage(coverUrls[3], null, Modifier.weight(1f).fillMaxSize())
                    }
                }
            }
            coverUrls.isNotEmpty() -> {
                LibraryImage(
                    model = coverUrls.first(),
                    contentDescription = null,
                    modifier = Modifier.fillMaxSize(),
                )
            }
            else -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(MaterialTheme.colorScheme.surfaceVariant),
                )
            }
        }
    }
}

@Composable
private fun PlaylistTrackRow(
    track: PlaylistTrackDetailRow,
    onClick: () -> Unit,
    onMoreClick: () -> Unit,
    showDragHandle: Boolean = false,
    dragHandleModifier: Modifier = Modifier,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (showDragHandle) {
            Icon(
                imageVector = Icons.Filled.DragHandle,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = dragHandleModifier.size(24.dp),
            )
        }
        Row(
            modifier = Modifier
                .weight(1f)
                .clickable(onClick = onClick),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            LibraryImage(
                model = track.thumbnailUrl,
                contentDescription = track.title,
                modifier = Modifier
                    .size(48.dp)
                    .clip(RoundedCornerShape(4.dp)),
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = track.title,
                    style = MaterialTheme.typography.bodyMedium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = formatTrackSubtitle(track),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        IconButton(onClick = onMoreClick) {
            Icon(Icons.Default.MoreVert, contentDescription = stringResource(R.string.library_song_more))
        }
    }
}

private fun formatTrackSubtitle(track: PlaylistTrackDetailRow): String {
    val artist = track.primaryArtistName?.takeIf { it.isNotBlank() }
    val duration = track.durationText?.takeIf { it.isNotBlank() }
        ?: track.durationSeconds.takeIf { it > 0 }?.let { seconds ->
            "%d:%02d".format(seconds / 60, seconds % 60)
        }
    return listOfNotNull(artist, duration).joinToString(" • ")
}
