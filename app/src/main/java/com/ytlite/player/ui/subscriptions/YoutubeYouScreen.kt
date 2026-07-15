package com.ytlite.player.ui.subscriptions

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import android.app.Application
import coil.ImageLoader
import coil.compose.AsyncImage
import com.ytlite.player.R
import com.ytlite.player.data.auth.UserSession
import com.ytlite.player.data.model.SubscriptionChannel
import com.ytlite.player.data.model.VideoItem
import com.ytlite.player.data.remote.youtube.YoutubeYouPlaylistPreview
import com.ytlite.player.ui.image.rememberYTLiteImageLoader
import com.ytlite.player.ui.image.thumbnailRequest
import kotlinx.coroutines.launch

data class YoutubePlaylistNav(
    val playlistId: String,
    val title: String,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun YoutubeYouScreen(
    session: UserSession.Authenticated,
    @Suppress("UNUSED_PARAMETER") onViewChannelClick: (SubscriptionChannel) -> Unit,
    onSwitchAccountClick: () -> Unit,
    onSubscriptionsViewAll: () -> Unit,
    onPlaylistsViewAll: () -> Unit,
    onPlaylistClick: (YoutubePlaylistNav) -> Unit,
    onChannelClick: (SubscriptionChannel) -> Unit,
    onVideoClick: (VideoItem) -> Unit,
    onCreatePlaylistClick: () -> Unit,
    @Suppress("UNUSED_PARAMETER") onYoutubeWebLoginClick: () -> Unit = {},
    onReauthClick: () -> Unit = {},
    youtubeCookieSessionEpoch: Int = 0,
    modifier: Modifier = Modifier,
    viewModel: YoutubeYouViewModel = viewModel(
        factory = YoutubeYouViewModel.factory(
            LocalContext.current.applicationContext as Application,
        ),
    ),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val imageLoader = rememberYTLiteImageLoader()
    val context = LocalContext.current
    val subscriptionsRowState = rememberLazyListState()
    val playlistsRowState = rememberLazyListState()
    val likedRowState = rememberLazyListState()

    LaunchedEffect(session.profile.userId, session.profile.channelId) {
        viewModel.refreshIfNeeded(session.profile.userId, session.profile.channelId)
    }

    LaunchedEffect(youtubeCookieSessionEpoch) {
        if (youtubeCookieSessionEpoch > 0) {
            viewModel.refresh(session.profile.userId)
        }
    }

    PullToRefreshBox(
        isRefreshing = uiState.isLoading && uiState.hasLoadedOnce,
        onRefresh = { viewModel.refresh(session.profile.userId) },
        modifier = modifier.fillMaxSize(),
    ) {
        when {
            uiState.isLoading && !uiState.hasLoadedOnce -> {
                Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            }
            uiState.errorMessage != null &&
                !uiState.isLoading &&
                uiState.history.isEmpty() &&
                uiState.subscriptions.isEmpty() &&
                uiState.playlists.isEmpty() &&
                uiState.watchLater.isEmpty() &&
                uiState.liked.isEmpty() &&
                uiState.yourVideos.isEmpty() -> {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(32.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Text(
                        text = stringResource(R.string.youtube_you_error_title),
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text(
                        text = uiState.errorMessage.orEmpty(),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 8.dp),
                    )
                    TextButton(onClick = { viewModel.refresh() }) {
                        Text(text = stringResource(R.string.home_retry))
                    }
                }
            }
            else -> {
                LazyColumn(
                    contentPadding = PaddingValues(bottom = 24.dp),
                    modifier = Modifier.fillMaxSize(),
                ) {
                    item(key = "profile") {
                        YoutubeYouProfileHeader(
                            displayName = uiState.displayName.ifBlank { session.profile.displayName },
                            handle = uiState.handle ?: session.profile.handle,
                            avatarUrl = uiState.avatarUrl ?: session.profile.avatarUrl,
                            onSwitchAccountClick = onSwitchAccountClick,
                            onGoogleAccountClick = {
                                context.startActivity(
                                    Intent(
                                        Intent.ACTION_VIEW,
                                        Uri.parse("https://myaccount.google.com/"),
                                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                                )
                            },
                        )
                    }

                    if (uiState.needsYoutubeReauth && uiState.hasLoadedOnce) {
                        item(key = "youtube_reauth_banner") {
                            Column(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 16.dp, vertical = 8.dp),
                            ) {
                                Text(
                                    text = stringResource(R.string.subscriptions_reauth_required),
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                TextButton(
                                    onClick = onReauthClick,
                                    modifier = Modifier.padding(top = 4.dp),
                                ) {
                                    Text(text = stringResource(R.string.sign_in_with_google))
                                }
                            }
                        }
                    }

                    // v1: History shelf / Connect YouTube banner hidden until cookie login is reliable.
                    item(key = "subscriptions") {
                        val rowState = subscriptionsRowState
                        YoutubeYouSection(
                            title = stringResource(R.string.youtube_you_subscriptions),
                            showViewAll = uiState.subscriptions.isNotEmpty(),
                            onViewAll = onSubscriptionsViewAll,
                            emptyText = stringResource(R.string.youtube_you_subscriptions_empty),
                            isEmpty = uiState.subscriptions.isEmpty(),
                            listState = rowState,
                        ) {
                            LazyRow(
                                state = rowState,
                                contentPadding = PaddingValues(horizontal = 12.dp),
                                horizontalArrangement = Arrangement.spacedBy(12.dp),
                            ) {
                                items(
                                    items = uiState.subscriptions,
                                    key = { it.channelId },
                                ) { channel ->
                                    YoutubeYouChannelCard(
                                        channel = channel,
                                        imageLoader = imageLoader,
                                        onClick = { onChannelClick(channel) },
                                    )
                                }
                            }
                        }
                    }

                    item(key = "playlists") {
                        val rowState = playlistsRowState
                        YoutubeYouSection(
                            title = stringResource(R.string.youtube_you_playlists),
                            showViewAll = uiState.playlists.isNotEmpty(),
                            onViewAll = onPlaylistsViewAll,
                            emptyText = stringResource(R.string.youtube_you_playlists_empty),
                            isEmpty = uiState.playlists.isEmpty(),
                            listState = rowState,
                            trailingAction = {
                                IconButton(onClick = onCreatePlaylistClick) {
                                    Icon(
                                        imageVector = Icons.Filled.Add,
                                        contentDescription = stringResource(
                                            R.string.youtube_you_new_playlist,
                                        ),
                                    )
                                }
                            },
                        ) {
                            LazyRow(
                                state = rowState,
                                contentPadding = PaddingValues(horizontal = 12.dp),
                                horizontalArrangement = Arrangement.spacedBy(12.dp),
                            ) {
                                items(
                                    items = uiState.playlists,
                                    key = { it.playlistId },
                                ) { playlist ->
                                    YoutubeYouPlaylistCard(
                                        playlist = playlist,
                                        imageLoader = imageLoader,
                                        onClick = {
                                            onPlaylistClick(
                                                YoutubePlaylistNav(
                                                    playlistId = playlist.playlistId,
                                                    title = playlist.title,
                                                ),
                                            )
                                        },
                                    )
                                }
                            }
                        }
                    }

                    // v1: Watch later shelf hidden until WebView cookie login is reliable.
                    item(key = "liked") {
                        val rowState = likedRowState
                        YoutubeYouSection(
                            title = stringResource(R.string.youtube_you_liked),
                            showViewAll = uiState.liked.isNotEmpty() &&
                                !uiState.likedPlaylistId.isNullOrBlank(),
                            onViewAll = {
                                val id = uiState.likedPlaylistId ?: return@YoutubeYouSection
                                onPlaylistClick(
                                    YoutubePlaylistNav(
                                        playlistId = id,
                                        title = context.getString(R.string.youtube_you_liked),
                                    ),
                                )
                            },
                            emptyIcon = Icons.Filled.ThumbUp,
                            emptyText = stringResource(R.string.youtube_you_liked_empty),
                            isEmpty = uiState.liked.isEmpty(),
                            listState = rowState,
                        ) {
                            YoutubeYouVideoRow(
                                videos = uiState.liked,
                                imageLoader = imageLoader,
                                listState = rowState,
                                onVideoClick = onVideoClick,
                            )
                        }
                    }
                    // v1: Your videos shelf hidden.
                }
            }
        }
    }
}

@Composable
private fun YoutubeYouProfileHeader(
    displayName: String,
    handle: String?,
    avatarUrl: String?,
    onSwitchAccountClick: () -> Unit,
    onGoogleAccountClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val imageLoader = rememberYTLiteImageLoader()
    val avatarLetter = displayName.firstOrNull()?.uppercaseChar()?.toString() ?: "?"

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (!avatarUrl.isNullOrBlank()) {
                val context = LocalContext.current
                AsyncImage(
                    model = thumbnailRequest(
                        context = context,
                        url = avatarUrl,
                        sizePx = (72 * context.resources.displayMetrics.density).toInt(),
                    ),
                    contentDescription = null,
                    imageLoader = imageLoader,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .size(72.dp)
                        .clip(CircleShape),
                )
            } else {
                Box(
                    modifier = Modifier
                        .size(72.dp)
                        .clip(CircleShape)
                        .background(Color(0xFFFF8A00)),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = avatarLetter,
                        style = MaterialTheme.typography.headlineMedium,
                        color = Color.White,
                    )
                }
            }
            Column(
                modifier = Modifier
                    .weight(1f)
                    .padding(start = 16.dp),
            ) {
                Text(
                    text = displayName,
                    style = MaterialTheme.typography.headlineSmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (!handle.isNullOrBlank()) {
                    Text(
                        text = handle,
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(top = 4.dp),
                    )
                }
            }
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Button(
                onClick = onSwitchAccountClick,
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(50),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant,
                    contentColor = MaterialTheme.colorScheme.onSurface,
                ),
            ) {
                Text(
                    text = stringResource(R.string.library_switch_account),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            OutlinedButton(
                onClick = onGoogleAccountClick,
                modifier = Modifier.weight(1f),
                shape = RoundedCornerShape(50),
            ) {
                Text(
                    text = stringResource(R.string.youtube_you_google_account),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun YoutubeYouSection(
    title: String,
    showViewAll: Boolean,
    onViewAll: () -> Unit,
    emptyText: String,
    isEmpty: Boolean,
    modifier: Modifier = Modifier,
    emptyIcon: ImageVector? = null,
    listState: LazyListState? = null,
    trailingAction: @Composable (() -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    val scope = rememberCoroutineScope()
    Column(modifier = modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier
                    .weight(1f)
                    .padding(start = 8.dp),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            trailingAction?.invoke()
            if (showViewAll) {
                TextButton(onClick = onViewAll) {
                    Text(text = stringResource(R.string.youtube_you_view_all))
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                    )
                }
            }
            if (listState != null && !isEmpty) {
                IconButton(
                    onClick = {
                        scope.launch {
                            val target = (listState.firstVisibleItemIndex - 2).coerceAtLeast(0)
                            listState.animateScrollToItem(target)
                        }
                    },
                ) {
                    Icon(Icons.Filled.ChevronLeft, contentDescription = null)
                }
                IconButton(
                    onClick = {
                        scope.launch {
                            val target = listState.firstVisibleItemIndex + 2
                            listState.animateScrollToItem(target)
                        }
                    },
                ) {
                    Icon(Icons.Filled.ChevronRight, contentDescription = null)
                }
            }
        }
        if (isEmpty) {
            YoutubeYouEmptyPlaceholder(
                text = emptyText,
                icon = emptyIcon,
            )
        } else {
            content()
        }
        Spacer(modifier = Modifier.height(12.dp))
    }
}

@Composable
private fun YoutubeYouEmptyPlaceholder(
    text: String,
    icon: ImageVector?,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier
                    .padding(end = 12.dp)
                    .size(28.dp),
            )
        }
        Text(
            text = text,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun YoutubeYouVideoRow(
    videos: List<VideoItem>,
    imageLoader: ImageLoader,
    listState: LazyListState,
    onVideoClick: (VideoItem) -> Unit,
) {
    LazyRow(
        state = listState,
        contentPadding = PaddingValues(horizontal = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        items(items = videos, key = { it.videoId }) { video ->
            YoutubeYouVideoCard(
                video = video,
                imageLoader = imageLoader,
                onClick = { onVideoClick(video) },
            )
        }
    }
}

@Composable
private fun YoutubeYouVideoCard(
    video: VideoItem,
    imageLoader: ImageLoader,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val thumbPx = (160 * context.resources.displayMetrics.density).toInt()
    Column(
        modifier = modifier
            .width(160.dp)
            .clickable(onClick = onClick),
    ) {
        Box {
            AsyncImage(
                model = thumbnailRequest(context, video.thumbnailUrl, sizePx = thumbPx),
                contentDescription = null,
                imageLoader = imageLoader,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(90.dp)
                    .clip(RoundedCornerShape(8.dp)),
            )
            video.durationText?.takeIf { it.isNotBlank() }?.let { duration ->
                Text(
                    text = duration,
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.White,
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(4.dp)
                        .background(Color.Black.copy(alpha = 0.75f), RoundedCornerShape(4.dp))
                        .padding(horizontal = 4.dp, vertical = 2.dp),
                )
            }
        }
        Text(
            text = video.title,
            style = MaterialTheme.typography.bodyMedium,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 6.dp),
        )
        Text(
            text = video.channelName,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun YoutubeYouChannelCard(
    channel: SubscriptionChannel,
    imageLoader: ImageLoader,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val avatarPx = (64 * context.resources.displayMetrics.density).toInt()
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = modifier
            .width(80.dp)
            .clickable(onClick = onClick),
    ) {
        AsyncImage(
            model = thumbnailRequest(context, channel.avatarUrl, sizePx = avatarPx),
            contentDescription = null,
            imageLoader = imageLoader,
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .size(64.dp)
                .clip(CircleShape),
        )
        Text(
            text = channel.title,
            style = MaterialTheme.typography.bodySmall,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 6.dp),
        )
    }
}

@Composable
fun YoutubeYouPlaylistCard(
    playlist: YoutubeYouPlaylistPreview,
    imageLoader: ImageLoader,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val thumbPx = (160 * context.resources.displayMetrics.density).toInt()
    Column(
        modifier = modifier
            .width(160.dp)
            .clickable(onClick = onClick),
    ) {
        Box {
            AsyncImage(
                model = thumbnailRequest(
                    context = context,
                    url = playlist.thumbnailUrl.orEmpty(),
                    sizePx = thumbPx,
                ),
                contentDescription = null,
                imageLoader = imageLoader,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(90.dp)
                    .clip(RoundedCornerShape(8.dp)),
            )
            playlist.itemCount?.let { count ->
                Text(
                    text = stringResource(R.string.youtube_you_video_count, count),
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.White,
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(4.dp)
                        .background(Color.Black.copy(alpha = 0.75f), RoundedCornerShape(4.dp))
                        .padding(horizontal = 4.dp, vertical = 2.dp),
                )
            }
        }
        Text(
            text = playlist.title,
            style = MaterialTheme.typography.bodyMedium,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 6.dp),
        )
        Text(
            text = stringResource(R.string.youtube_you_playlist_subtitle),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}
