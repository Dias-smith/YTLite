package com.ytlite.player.ui.search

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import android.app.Application
import com.ytlite.player.R
import com.ytlite.player.data.model.SearchResultItem
import com.ytlite.player.data.model.SearchScreenState
import com.ytlite.player.data.model.SubscriptionChannel
import kotlinx.coroutines.launch

@Composable
fun SearchScreen(
    onVideoClick: (String) -> Unit,
    onChannelClick: (SubscriptionChannel) -> Unit,
    modifier: Modifier = Modifier,
    viewModel: SearchViewModel = viewModel(
        factory = SearchViewModel.factory(LocalContext.current.applicationContext as Application),
    ),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    val comingSoon = stringResource(R.string.placeholder_coming_soon)

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
                    onVideoClick = onVideoClick,
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding),
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
                        .padding(innerPadding),
                )
            }
            else -> {
                SearchContent(
                    uiState = uiState,
                    onQueryChange = viewModel::onQueryChange,
                    onClearQuery = viewModel::onClearQuery,
                    onSubmitSearch = { viewModel.onSubmitSearch() },
                    onVoiceClick = {
                        scope.launch { snackbarHostState.showSnackbar(comingSoon) }
                    },
                    onSuggestionClick = viewModel::onSuggestionClick,
                    onHistoryQueryClick = viewModel::onHistoryQueryClick,
                    onRecentClick = viewModel::onRecentClick,
                    onRecentLongPress = viewModel::requestDeleteRecent,
                    onClearRecentClicks = viewModel::clearRecentClicks,
                    onClearQueryHistory = viewModel::clearQueryHistory,
                    onDiscoveryOpen = viewModel::onDiscoveryOpen,
                    onResultTabSelected = viewModel::onResultTabSelected,
                    onLoadMoreResults = viewModel::loadMoreResults,
                    onVideoClick = { videoId ->
                        onVideoClick(videoId)
                    },
                    onChannelClick = { channel ->
                        onChannelClick(channel)
                    },
                    onResultChannelClick = { item ->
                        onChannelClick(viewModel.toSubscriptionChannel(item))
                    },
                    onPlaylistClick = viewModel::openPlaylistBrowse,
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(innerPadding),
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
    onVoiceClick: () -> Unit,
    onSuggestionClick: (com.ytlite.player.data.model.SearchSuggestion) -> Unit,
    onHistoryQueryClick: (String) -> Unit,
    onRecentClick: (com.ytlite.player.data.local.entity.SearchRecentClickEntity) -> Unit,
    onRecentLongPress: (String) -> Unit,
    onClearRecentClicks: () -> Unit,
    onClearQueryHistory: () -> Unit,
    onDiscoveryOpen: (com.ytlite.player.data.model.DiscoveryType) -> Unit,
    onResultTabSelected: (com.ytlite.player.data.model.SearchResultTab) -> Unit,
    onLoadMoreResults: () -> Unit,
    onVideoClick: (String) -> Unit,
    onChannelClick: (SubscriptionChannel) -> Unit,
    onResultChannelClick: (SearchResultItem.Channel) -> Unit,
    onPlaylistClick: (SearchResultItem.Playlist) -> Unit,
    modifier: Modifier = Modifier,
) {
    androidx.compose.foundation.layout.Column(modifier = modifier) {
        SearchBar(
            query = uiState.query,
            onQueryChange = onQueryChange,
            onClear = onClearQuery,
            onSubmit = onSubmitSearch,
            onVoiceClick = onVoiceClick,
        )
        when (uiState.screenState) {
            SearchScreenState.DefaultHub -> {
                DefaultHubView(
                    recentClicks = uiState.recentClicks,
                    queryHistory = uiState.queryHistory,
                    onRecentClick = onRecentClick,
                    onRecentLongPress = onRecentLongPress,
                    onClearRecentClicks = onClearRecentClicks,
                    onHistoryQueryClick = onHistoryQueryClick,
                    onClearQueryHistory = onClearQueryHistory,
                    onDiscoveryOpen = onDiscoveryOpen,
                )
            }
            is SearchScreenState.Suggestions -> {
                SearchSuggestionsList(
                    suggestions = uiState.suggestions,
                    isLoading = uiState.isSuggestionsLoading,
                    onSuggestionClick = onSuggestionClick,
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
