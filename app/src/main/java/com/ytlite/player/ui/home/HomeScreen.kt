package com.ytlite.player.ui.home

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
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.ytlite.player.R
import com.ytlite.player.data.model.VideoItem
import com.ytlite.player.ui.image.rememberYTLiteImageLoader

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    onVideoClick: (VideoItem) -> Unit,
    modifier: Modifier = Modifier,
    viewModel: HomeViewModel = viewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val imageLoader = rememberYTLiteImageLoader()
    val listState = rememberLazyListState()

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
        CategoryFilterBar(
            categories = uiState.categories,
            selectedCategoryId = uiState.selectedCategoryId,
            onCategorySelected = viewModel::selectCategory,
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
                    ErrorContent(
                        message = uiState.errorMessage.orEmpty(),
                        onRetry = { viewModel.loadFeed() },
                        modifier = Modifier.fillMaxSize(),
                    )
                }
                uiState.videos.isEmpty() -> {
                    EmptyContent(modifier = Modifier.fillMaxSize())
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
                                onClick = { onVideoClick(video) },
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
private fun ErrorContent(
    message: String,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(modifier = modifier, contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.padding(24.dp),
        ) {
            Text(
                text = stringResource(R.string.home_error),
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                text = message,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Button(onClick = onRetry) {
                Text(text = stringResource(R.string.home_retry))
            }
        }
    }
}

@Composable
private fun EmptyContent(modifier: Modifier = Modifier) {
    Box(modifier = modifier, contentAlignment = Alignment.Center) {
        Text(
            text = stringResource(R.string.home_empty),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
