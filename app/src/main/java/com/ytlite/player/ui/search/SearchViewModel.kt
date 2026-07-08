package com.ytlite.player.ui.search

import android.app.Application
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.ytlite.player.data.local.entity.SearchQueryEntity
import com.ytlite.player.data.local.entity.SearchRecentClickEntity
import com.ytlite.player.data.model.DiscoveryType
import com.ytlite.player.data.model.SearchRecentType
import com.ytlite.player.data.model.SearchResultItem
import com.ytlite.player.data.model.SearchResultTab
import com.ytlite.player.data.model.SearchScreenState
import com.ytlite.player.data.model.SearchSuggestion
import com.ytlite.player.data.model.SubscriptionChannel
import com.ytlite.player.data.parser.BrowsePage
import com.ytlite.player.data.repository.SearchRepository
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class SearchUiState(
    val query: String = "",
    val screenState: SearchScreenState = SearchScreenState.DefaultHub,
    val queryHistory: List<SearchQueryEntity> = emptyList(),
    val recentClicks: List<SearchRecentClickEntity> = emptyList(),
    val suggestions: List<SearchSuggestion> = emptyList(),
    val isSuggestionsLoading: Boolean = false,
    val resultItems: List<SearchResultItem> = emptyList(),
    val resultsContinuation: String? = null,
    val isResultsLoading: Boolean = false,
    val isResultsLoadingMore: Boolean = false,
    val resultsError: String? = null,
    val discoveryPage: BrowsePage? = null,
    val isDiscoveryLoading: Boolean = false,
    val discoveryError: String? = null,
    val pendingDeleteRecentId: String? = null,
)

@OptIn(FlowPreview::class)
class SearchViewModel(
    application: Application,
    private val repository: SearchRepository = SearchRepository.getInstance(application),
) : ViewModel() {

    private val mutableState = MutableStateFlow(SearchUiState())

    val uiState: StateFlow<SearchUiState> = combine(
        mutableState,
        repository.observeQueryHistory(),
        repository.observeRecentClicks(),
    ) { state, history, recent ->
        state.copy(queryHistory = history, recentClicks = recent)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), SearchUiState())

    private val debouncedQuery = mutableState
        .map { it.query }
        .debounce(300)
        .distinctUntilChanged()

    init {
        viewModelScope.launch {
            debouncedQuery.collect { query ->
                val state = mutableState.value.screenState
                if (query.isBlank()) {
                    mutableState.update { it.copy(suggestions = emptyList()) }
                    if (state is SearchScreenState.Suggestions) {
                        mutableState.update { it.copy(screenState = SearchScreenState.DefaultHub) }
                    }
                    return@collect
                }
                if (state !is SearchScreenState.Suggestions && state !is SearchScreenState.Results) {
                    mutableState.update {
                        it.copy(screenState = SearchScreenState.Suggestions(query))
                    }
                }
                loadSuggestions(query)
            }
        }
    }

    fun onQueryChange(query: String) {
        mutableState.update { current ->
            val nextState = when {
                query.isBlank() -> SearchScreenState.DefaultHub
                current.screenState is SearchScreenState.Results ->
                    SearchScreenState.Suggestions(query)
                else -> current.screenState
            }
            current.copy(
                query = query,
                screenState = nextState,
                resultItems = if (query.isBlank()) emptyList() else current.resultItems,
                resultsContinuation = if (query.isBlank()) null else current.resultsContinuation,
                resultsError = if (query.isBlank()) null else current.resultsError,
            )
        }
    }

    fun onClearQuery() {
        mutableState.value = SearchUiState(
            queryHistory = mutableState.value.queryHistory,
            recentClicks = mutableState.value.recentClicks,
        )
    }

    fun onSubmitSearch(query: String = mutableState.value.query) {
        val trimmed = query.trim()
        if (trimmed.isBlank()) return
        mutableState.update {
            it.copy(query = trimmed, screenState = SearchScreenState.Results(trimmed))
        }
        viewModelScope.launch { repository.saveQuery(trimmed) }
        loadResults(trimmed, SearchResultTab.ALL, reset = true)
    }

    fun onSuggestionClick(suggestion: SearchSuggestion) {
        when (suggestion) {
            is SearchSuggestion.Query -> onSubmitSearch(suggestion.text)
            is SearchSuggestion.Channel -> {
                viewModelScope.launch {
                    repository.saveQuery(suggestion.title)
                    repository.recordRecentClick(
                        targetId = suggestion.channelId,
                        type = SearchRecentType.CHANNEL,
                        title = suggestion.title,
                        subtitle = suggestion.subtitle,
                        thumbnailUrl = suggestion.avatarUrl.orEmpty(),
                    )
                }
                onSubmitSearch(suggestion.title)
            }
            is SearchSuggestion.Video -> {
                viewModelScope.launch {
                    repository.saveQuery(suggestion.title)
                    repository.recordRecentClick(
                        targetId = suggestion.videoId,
                        type = SearchRecentType.VIDEO,
                        title = suggestion.title,
                        subtitle = suggestion.subtitle,
                        thumbnailUrl = suggestion.thumbnailUrl.orEmpty(),
                    )
                }
                onSubmitSearch(suggestion.title)
            }
        }
    }

    fun onHistoryQueryClick(query: String) {
        mutableState.update {
            it.copy(query = query, screenState = SearchScreenState.Suggestions(query))
        }
    }

    fun onRecentClick(entity: SearchRecentClickEntity) {
        onSubmitSearch(entity.title)
    }

    fun onResultTabSelected(tab: SearchResultTab) {
        val current = mutableState.value.screenState as? SearchScreenState.Results ?: return
        mutableState.update { it.copy(screenState = current.copy(tab = tab)) }
        loadResults(current.query, tab, reset = true)
    }

    fun loadMoreResults() {
        val current = mutableState.value.screenState as? SearchScreenState.Results ?: return
        val continuation = mutableState.value.resultsContinuation ?: return
        if (mutableState.value.isResultsLoadingMore) return
        loadResults(current.query, current.tab, continuation = continuation, reset = false)
    }

    fun onDiscoveryOpen(type: DiscoveryType) {
        mutableState.update {
            it.copy(
                screenState = SearchScreenState.SubCategory(type),
                discoveryPage = null,
                discoveryError = null,
                isDiscoveryLoading = true,
            )
        }
        viewModelScope.launch {
            runCatching { repository.browseDiscovery(type) }
                .onSuccess { page ->
                    mutableState.update { it.copy(discoveryPage = page, isDiscoveryLoading = false) }
                }
                .onFailure { error ->
                    mutableState.update {
                        it.copy(discoveryError = error.message, isDiscoveryLoading = false)
                    }
                }
        }
    }

    fun onDiscoveryBack() {
        mutableState.update {
            it.copy(screenState = SearchScreenState.DefaultHub, discoveryPage = null)
        }
    }

    fun clearRecentClicks() {
        viewModelScope.launch { repository.clearRecentClicks() }
    }

    fun clearQueryHistory() {
        viewModelScope.launch { repository.clearQueryHistory() }
    }

    fun requestDeleteRecent(targetId: String) {
        mutableState.update { it.copy(pendingDeleteRecentId = targetId) }
    }

    fun confirmDeleteRecent() {
        val id = mutableState.value.pendingDeleteRecentId ?: return
        mutableState.update { it.copy(pendingDeleteRecentId = null) }
        viewModelScope.launch { repository.deleteRecentClick(id) }
    }

    fun dismissDeleteRecent() {
        mutableState.update { it.copy(pendingDeleteRecentId = null) }
    }

    fun toSubscriptionChannel(item: SearchResultItem.Channel): SubscriptionChannel =
        SubscriptionChannel(
            channelId = item.channelId,
            title = item.title,
            handle = null,
            avatarUrl = item.thumbnailUrl.orEmpty(),
            subscriberCountText = item.subtitle.takeIf { it.isNotBlank() },
            description = null,
        )

    private fun loadSuggestions(query: String) {
        viewModelScope.launch {
            mutableState.update { it.copy(isSuggestionsLoading = true) }
            val historyList = uiState.value.queryHistory.map { it.query }
            runCatching {
                repository.fetchSuggestions(query, historyList)
            }.onSuccess { suggestions ->
                mutableState.update { it.copy(suggestions = suggestions) }
            }
            mutableState.update { it.copy(isSuggestionsLoading = false) }
        }
    }

    private fun loadResults(
        query: String,
        tab: SearchResultTab,
        continuation: String? = null,
        reset: Boolean,
    ) {
        viewModelScope.launch {
            if (reset) {
                mutableState.update { it.copy(isResultsLoading = true, resultsError = null) }
            } else {
                mutableState.update { it.copy(isResultsLoadingMore = true) }
            }
            runCatching {
                repository.search(query, tab, continuation)
            }.onSuccess { page ->
                mutableState.update { current ->
                    val items = if (reset) {
                        page.items
                    } else {
                        val merged = LinkedHashMap<String, SearchResultItem>()
                        current.resultItems.forEach { merged[it.id] = it }
                        page.items.forEach { merged[it.id] = it }
                        merged.values.toList()
                    }
                    current.copy(
                        resultItems = items,
                        resultsContinuation = page.continuation,
                    )
                }
            }.onFailure { error ->
                if (reset) {
                    mutableState.update {
                        it.copy(resultsError = error.message, resultItems = emptyList())
                    }
                }
            }
            mutableState.update { it.copy(isResultsLoading = false, isResultsLoadingMore = false) }
        }
    }

    companion object {
        fun factory(application: Application): ViewModelProvider.Factory = viewModelFactory {
            initializer { SearchViewModel(application) }
        }
    }
}
