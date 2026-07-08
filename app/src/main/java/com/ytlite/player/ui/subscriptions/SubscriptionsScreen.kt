package com.ytlite.player.ui.subscriptions

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import android.app.Application
import com.ytlite.player.R
import com.ytlite.player.data.auth.UserSession
import com.ytlite.player.data.model.SubscriptionChannel
import com.ytlite.player.ui.common.SignInPromptScreen
import com.ytlite.player.ui.common.SubscriptionsIllustration
import com.ytlite.player.ui.home.VideoFeedItem
import com.ytlite.player.ui.image.rememberYTLiteImageLoader

@Composable
fun SubscriptionsScreen(
    session: UserSession?,
    onSignInClick: () -> Unit,
    onVideoClick: (String) -> Unit,
    onChannelListClick: () -> Unit,
    onChannelClick: (SubscriptionChannel) -> Unit = {},
    modifier: Modifier = Modifier,
    viewModel: SubscriptionsViewModel = viewModel(
        factory = SubscriptionsViewModel.factory(
            LocalContext.current.applicationContext as Application,
        ),
    ),
) {
    when (session) {
        is UserSession.Authenticated -> SubscriptionsAuthenticatedContent(
            userId = session.profile.userId,
            onVideoClick = onVideoClick,
            onChannelListClick = onChannelListClick,
            onChannelClick = onChannelClick,
            viewModel = viewModel,
            modifier = modifier,
        )
        else -> SignInPromptScreen(
            title = stringResource(R.string.subscriptions_sign_in_title),
            description = stringResource(R.string.subscriptions_sign_in_description),
            illustration = { SubscriptionsIllustration() },
            onSignInClick = onSignInClick,
            modifier = modifier,
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SubscriptionsAuthenticatedContent(
    userId: String,
    onVideoClick: (String) -> Unit,
    onChannelListClick: () -> Unit,
    onChannelClick: (SubscriptionChannel) -> Unit,
    viewModel: SubscriptionsViewModel,
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val imageLoader = rememberYTLiteImageLoader()
    val listState = rememberLazyListState()

    LaunchedEffect(userId) {
        viewModel.refreshIfNeeded(userId)
    }

    val shouldLoadMore by remember {
        derivedStateOf {
            val layoutInfo = listState.layoutInfo
            val lastVisible = layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
            lastVisible >= layoutInfo.totalItemsCount - 3
        }
    }

    LaunchedEffect(shouldLoadMore, uiState.continuation, uiState.isLoadingMore) {
        if (shouldLoadMore && uiState.continuation != null && !uiState.isLoadingMore) {
            viewModel.loadMore()
        }
    }

    Column(modifier = modifier.fillMaxSize()) {
        TextButton(
            onClick = onChannelListClick,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
        ) {
            Text(text = stringResource(R.string.subscriptions_all_channels))
        }

        SubscriptionChannelsRow(
            channels = uiState.channels,
            imageLoader = imageLoader,
            onChannelClick = onChannelClick,
            onLoadMore = { viewModel.loadMoreChannels() },
            hasMore = uiState.channelsContinuation != null,
            isLoadingMore = uiState.isLoadingMoreChannels,
        )

        PullToRefreshBox(
            isRefreshing = uiState.isLoading && uiState.videos.isNotEmpty(),
            onRefresh = { viewModel.refresh() },
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
        ) {
            when {
                uiState.isLoading && uiState.videos.isEmpty() -> {
                    LoadingContent(modifier = Modifier.fillMaxSize())
                }
                uiState.errorMessage != null && uiState.videos.isEmpty() -> {
                    SubscriptionErrorContent(
                        message = uiState.errorMessage.orEmpty(),
                        onRetry = { viewModel.refresh() },
                        modifier = Modifier.fillMaxSize(),
                    )
                }
                uiState.videos.isEmpty() -> {
                    SubscriptionsEmptyContent(modifier = Modifier.fillMaxSize())
                }
                else -> {
                    LazyColumn(
                        state = listState,
                        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        items(
                            items = uiState.videos,
                            key = { it.videoId },
                        ) { video ->
                            VideoFeedItem(
                                video = video,
                                imageLoader = imageLoader,
                                onClick = { onVideoClick(video.videoId) },
                            )
                        }
                        if (uiState.isLoadingMore) {
                            item(key = "loading_more") {
                                Box(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(vertical = 16.dp),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    CircularProgressIndicator()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun LoadingContent(modifier: Modifier = Modifier) {
    Box(modifier = modifier, contentAlignment = Alignment.Center) {
        CircularProgressIndicator()
    }
}

@Composable
private fun SubscriptionsEmptyContent(
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.padding(horizontal = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        SubscriptionsIllustration()
        Text(
            text = stringResource(R.string.subscriptions_empty_title),
            style = MaterialTheme.typography.titleLarge,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 32.dp),
        )
        Text(
            text = stringResource(R.string.subscriptions_empty_description),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 12.dp),
        )
    }
}
