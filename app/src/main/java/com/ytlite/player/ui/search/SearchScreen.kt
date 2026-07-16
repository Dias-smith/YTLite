package com.ytlite.player.ui.search

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import android.app.Application
import com.ytlite.player.R
import com.ytlite.player.data.model.BrowseVideosKind
import com.ytlite.player.data.model.SearchResultItem
import com.ytlite.player.data.model.SearchScreenState
import com.ytlite.player.data.model.SubscriptionChannel
import com.ytlite.player.data.model.VideoItem
import com.ytlite.player.playback.QueueItem
import com.ytlite.player.ui.player.toQueueItem

@Composable
fun SearchScreen(
    onVideoClick: (VideoItem) -> Unit,
    onChannelClick: (SubscriptionChannel) -> Unit,
    onPlayPlaylist: (List<QueueItem>, Int, String) -> Unit,
    modifier: Modifier = Modifier,
    viewModel: SearchViewModel = viewModel(
        factory = SearchViewModel.factory(LocalContext.current.applicationContext as Application),
    ),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }

    if (uiState.pendingDeleteRecentId != null) {
        AlertDialog(
            onDismissRequest = viewModel::dismissDeleteRecent,
            title = { Text(stringResource(R.string.search_delete_recent_title)) },
            text = { Text(stringResource(R.string.search_delete_recent_message)) },
            confirmButton = {
                TextButton(onClick = viewModel::confirmDeleteRecent) {
                    Text(stringResource(R.string.search_delete))
                }
            },
            dismissButton = {
                TextButton(onClick = viewModel::dismissDeleteRecent) {
                    Text(stringResource(R.string.library_cancel))
                }
            },
        )
    }

    Scaffold(
        modifier = modifier.fillMaxSize(),
        contentWindowInsets = WindowInsets(0, 0, 0, 0),
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { innerPadding ->
        when (val state = uiState.screenState) {
            is SearchScreenState.BrowseVideos -> {
                BrowseVideosScreen(
                    title = state.title,
                    videos = uiState.browseVideos,
                    isLoading = uiState.isBrowseLoading,
                    isLoadingMore = uiState.isBrowseLoadingMore,
                    error = uiState.browseError,
                    hasMore = uiState.browseContinuation != null,
                    onBack = viewModel::onBrowseBack,
                    onRefresh = viewModel::refreshBrowse,
                    onLoadMore = viewModel::loadMoreBrowse,
                    onVideoClick = { video ->
                        val queueItems = uiState.browseVideos.map { it.toQueueItem() }
                        val startIndex = queueItems.indexOfFirst { it.videoId == video.videoId }
                            .coerceAtLeast(0)
                        if (queueItems.isNotEmpty()) {
                            val sourceId = when (state.kind) {
                                BrowseVideosKind.PLAYLIST -> "yt_playlist:${state.browseId}"
                                BrowseVideosKind.MOOD -> "yt_browse:${state.browseId}"
                            }
                            onPlayPlaylist(queueItems, startIndex, sourceId)
                        } else {
                            onVideoClick(video)
                        }
                    },
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(bottom = innerPadding.calculateBottomPadding()),
                )
            }
            is SearchScreenState.SubCategory -> {
                DiscoverySubPage(
                    type = state.type,
                    page = uiState.discoveryPage,
                    isLoading = uiState.isDiscoveryLoading,
                    error = uiState.discoveryError,
                    onBack = viewModel::onDiscoveryBack,
                    onVideoClick = onVideoClick,
                    onMoodClick = viewModel::openMoodBrowse,
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(bottom = innerPadding.calculateBottomPadding()),
                )
            }
            else -> {
                SearchContent(
                    uiState = uiState,
                    onQueryChange = viewModel::onQueryChange,
                    onClearQuery = viewModel::onClearQuery,
                    onSubmitSearch = { viewModel.onSubmitSearch() },
                    onSuggestionClick = viewModel::onSuggestionClick,
                    onSuggestionFill = viewModel::onSuggestionFill,
                    onHistoryQueryClick = viewModel::onHistoryQueryClick,
                    onHistoryQueryFill = viewModel::onHistoryQueryFill,
                    onRecentClick = viewModel::onRecentClick,
                    onRecentLongPress = viewModel::requestDeleteRecent,
                    onClearRecentClicks = viewModel::clearRecentClicks,
                    onClearQueryHistory = viewModel::clearQueryHistory,
                    onHotKeywordClick = viewModel::onSubmitSearch,
                    onResultTabSelected = viewModel::onResultTabSelected,
                    onLoadMoreResults = viewModel::loadMoreResults,
                    onVideoClick = onVideoClick,
                    onChannelClick = { channel ->
                        onChannelClick(channel)
                    },
                    onResultChannelClick = { item ->
                        onChannelClick(viewModel.toSubscriptionChannel(item))
                    },
                    onPlaylistClick = viewModel::openPlaylistBrowse,
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(bottom = innerPadding.calculateBottomPadding()),
                )
            }
        }
    }
}

@Composable
private fun SearchContent(
    uiState: SearchUiState,
    onQueryChange: (String) -> Unit,
    onClearQuery: () -> Unit,
    onSubmitSearch: () -> Unit,
    onSuggestionClick: (com.ytlite.player.data.model.SearchSuggestion) -> Unit,
    onSuggestionFill: (com.ytlite.player.data.model.SearchSuggestion) -> Unit,
    onHistoryQueryClick: (String) -> Unit,
    onHistoryQueryFill: (String) -> Unit,
    onRecentClick: (com.ytlite.player.data.local.entity.SearchRecentClickEntity) -> Unit,
    onRecentLongPress: (String) -> Unit,
    onClearRecentClicks: () -> Unit,
    onClearQueryHistory: () -> Unit,
    onHotKeywordClick: (String) -> Unit,
    onResultTabSelected: (com.ytlite.player.data.model.SearchResultTab) -> Unit,
    onLoadMoreResults: () -> Unit,
    onVideoClick: (VideoItem) -> Unit,
    onChannelClick: (SubscriptionChannel) -> Unit,
    onResultChannelClick: (SearchResultItem.Channel) -> Unit,
    onPlaylistClick: (SearchResultItem.Playlist) -> Unit,
    modifier: Modifier = Modifier,
) {
    val focusManager = LocalFocusManager.current
    val keyboardController = LocalSoftwareKeyboardController.current
    val showingResults = uiState.screenState is SearchScreenState.Results

    LaunchedEffect(showingResults) {
        if (showingResults) {
            focusManager.clearFocus(force = true)
            keyboardController?.hide()
        }
    }

    androidx.compose.foundation.layout.Column(modifier = modifier) {
        SearchBar(
            query = uiState.query,
            onQueryChange = onQueryChange,
            onClear = onClearQuery,
            onSubmit = {
                focusManager.clearFocus(force = true)
                keyboardController?.hide()
                onSubmitSearch()
            },
        )
        when (uiState.screenState) {
            SearchScreenState.DefaultHub -> {
                DefaultHubView(
                    recentClicks = uiState.recentClicks,
                    queryHistory = uiState.queryHistory,
                    hotKeywords = uiState.hotKeywords,
                    onRecentClick = onRecentClick,
                    onRecentLongPress = onRecentLongPress,
                    onClearRecentClicks = onClearRecentClicks,
                    onHistoryQueryClick = onHistoryQueryClick,
                    onHistoryQueryFill = onHistoryQueryFill,
                    onClearQueryHistory = onClearQueryHistory,
                    onHotKeywordClick = onHotKeywordClick,
                )
            }
            is SearchScreenState.Suggestions -> {
                SearchSuggestionsList(
                    suggestions = uiState.suggestions,
                    isLoading = uiState.isSuggestionsLoading,
                    onSuggestionClick = onSuggestionClick,
                    onSuggestionFill = onSuggestionFill,
                )
            }
            is SearchScreenState.Results -> {
                SearchResultsScreen(
                    query = uiState.screenState.query,
                    activeTab = uiState.screenState.tab,
                    items = uiState.resultItems,
                    isLoading = uiState.isResultsLoading,
                    isLoadingMore = uiState.isResultsLoadingMore,
                    error = uiState.resultsError,
                    hasMore = uiState.resultsContinuation != null,
                    onTabSelected = onResultTabSelected,
                    onLoadMore = onLoadMoreResults,
                    onVideoClick = onVideoClick,
                    onChannelClick = onResultChannelClick,
                    onPlaylistClick = onPlaylistClick,
                )
            }
            is SearchScreenState.SubCategory -> Unit
            is SearchScreenState.BrowseVideos -> Unit
        }
    }
}
