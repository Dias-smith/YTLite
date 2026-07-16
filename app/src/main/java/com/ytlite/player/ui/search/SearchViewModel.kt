package com.ytlite.player.ui.search

import android.app.Application
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.ytlite.player.data.local.entity.SearchQueryEntity
import com.ytlite.player.data.local.entity.SearchRecentClickEntity
import com.ytlite.player.data.model.BrowseVideosKind
import com.ytlite.player.data.model.DiscoveryType
import com.ytlite.player.data.model.SearchRecentType
import com.ytlite.player.data.model.SearchResultItem
import com.ytlite.player.data.model.SearchResultTab
import com.ytlite.player.data.model.SearchScreenState
import com.ytlite.player.data.model.SearchSuggestion
import com.ytlite.player.data.model.SubscriptionChannel
import com.ytlite.player.data.model.VideoItem
import com.ytlite.player.data.parser.BrowseMoodItem
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
    val hotKeywords: List<String> = emptyList(),
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
    val browseVideos: List<VideoItem> = emptyList(),
    val browseContinuation: String? = null,
    val isBrowseLoading: Boolean = false,
    val isBrowseLoadingMore: Boolean = false,
    val browseError: String? = null,
)

@OptIn(FlowPreview::class)
class SearchViewModel(
    application: Application,
    private val repository: SearchRepository = SearchRepository.getInstance(application),
) : ViewModel() {

    private val mutableState = MutableStateFlow(SearchUiState())
    private var stateBeforeBrowse: SearchScreenState? = null

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
        loadHotKeywords()
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
                // History / hot keyword / keyboard submit land on Results — do not
                // bounce into the suggestions pane for that query update.
                if (state is SearchScreenState.Results) {
                    return@collect
                }
                if (state !is SearchScreenState.Suggestions) {
                    mutableState.update {
                        it.copy(screenState = SearchScreenState.Suggestions(query))
                    }
                }
                loadSuggestions(query)
            }
        }
    }

    fun loadHotKeywords() {
        viewModelScope.launch {
            val keywords = repository.fetchHotKeywords()
            mutableState.update { it.copy(hotKeywords = keywords) }
        }
    }

    fun onQueryChange(query: String) {
        mutableState.update { current ->
            val nextState = when {
                query.isBlank() -> SearchScreenState.DefaultHub
                current.screenState is SearchScreenState.Results -> {
                    val results = current.screenState as SearchScreenState.Results
                    // Keep results when the field is re-synced to the submitted query
                    // (e.g. after IME dismiss). Only leave when the user edits it.
                    if (query.trim() == results.query) current.screenState
                    else SearchScreenState.Suggestions(query)
                }
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
            hotKeywords = mutableState.value.hotKeywords,
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

    fun onSuggestionFill(suggestion: SearchSuggestion) {
        val text = when (suggestion) {
            is SearchSuggestion.Query -> suggestion.text
            is SearchSuggestion.Channel -> suggestion.title
            is SearchSuggestion.Video -> suggestion.title
        }
        mutableState.update {
            it.copy(query = text, screenState = SearchScreenState.Suggestions(text))
        }
    }

    fun onHistoryQueryClick(query: String) {
        onSubmitSearch(query)
    }

    fun onHistoryQueryFill(query: String) {
        val trimmed = query.trim()
        if (trimmed.isBlank()) return
        mutableState.update {
            it.copy(query = trimmed, screenState = SearchScreenState.Suggestions(trimmed))
        }
    }

    fun onRecentClick(entity: SearchRecentClickEntity) {
        when (entity.type) {
            SearchRecentType.PLAYLIST.name -> {
                openPlaylistBrowse(
                    SearchResultItem.Playlist(
                        id = entity.targetId,
                        playlistId = entity.targetId,
                        title = entity.title,
                        subtitle = entity.subtitle,
                        thumbnailUrl = entity.thumbnailUrl.takeIf { it.isNotBlank() },
                    ),
                )
            }
            else -> onSubmitSearch(entity.title)
        }
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

    fun openPlaylistBrowse(playlist: SearchResultItem.Playlist) {
        stateBeforeBrowse = mutableState.value.screenState
        mutableState.update {
            it.copy(
                screenState = SearchScreenState.BrowseVideos(
                    browseId = playlist.playlistId,
                    title = playlist.title,
                    kind = BrowseVideosKind.PLAYLIST,
                ),
                browseVideos = emptyList(),
                browseContinuation = null,
                browseError = null,
                isBrowseLoading = true,
            )
        }
        viewModelScope.launch {
            repository.recordRecentClick(
                targetId = playlist.playlistId,
                type = SearchRecentType.PLAYLIST,
                title = playlist.title,
                subtitle = playlist.subtitle,
                thumbnailUrl = playlist.thumbnailUrl.orEmpty(),
            )
        }
        loadBrowse(reset = true)
    }

    fun openMoodBrowse(mood: BrowseMoodItem) {
        stateBeforeBrowse = mutableState.value.screenState
        mutableState.update {
            it.copy(
                screenState = SearchScreenState.BrowseVideos(
                    browseId = mood.browseId,
                    title = mood.title,
                    kind = BrowseVideosKind.MOOD,
                ),
                browseVideos = emptyList(),
                browseContinuation = null,
                browseError = null,
                isBrowseLoading = true,
            )
        }
        loadBrowse(reset = true)
    }

    fun onBrowseBack() {
        val returnState = stateBeforeBrowse ?: SearchScreenState.DefaultHub
        stateBeforeBrowse = null
        mutableState.update {
            it.copy(
                screenState = returnState,
                browseVideos = emptyList(),
                browseContinuation = null,
                browseError = null,
                isBrowseLoading = false,
                isBrowseLoadingMore = false,
            )
        }
    }

    fun refreshBrowse() {
        loadBrowse(reset = true)
    }

    fun loadMoreBrowse() {
        val continuation = mutableState.value.browseContinuation ?: return
        if (mutableState.value.isBrowseLoadingMore || mutableState.value.isBrowseLoading) return
        loadBrowse(reset = false, continuation = continuation)
    }

    private fun loadBrowse(reset: Boolean, continuation: String? = null) {
        val browseState = mutableState.value.screenState as? SearchScreenState.BrowseVideos ?: return
        viewModelScope.launch {
            if (reset) {
                mutableState.update { it.copy(isBrowseLoading = true, browseError = null) }
            } else {
                mutableState.update { it.copy(isBrowseLoadingMore = true) }
            }
            val result = runCatching {
                when (browseState.kind) {
                    BrowseVideosKind.PLAYLIST -> repository.fetchPlaylistVideos(
                        browseState.browseId,
                        continuation,
                    )
                    BrowseVideosKind.MOOD -> repository.fetchBrowseVideos(
                        browseState.browseId,
                        continuation,
                    )
                }
            }
            result.onSuccess { page ->
                mutableState.update { current ->
                    val videos = if (reset) {
                        page.rankedVideos
                    } else {
                        val merged = LinkedHashMap<String, VideoItem>()
                        current.browseVideos.forEach { merged[it.videoId] = it }
                        page.rankedVideos.forEach { merged[it.videoId] = it }
                        merged.values.toList()
                    }
                    current.copy(
                        browseVideos = videos,
                        browseContinuation = page.continuation,
                    )
                }
            }.onFailure { error ->
                if (reset) {
                    mutableState.update {
                        it.copy(browseError = error.message, browseVideos = emptyList())
                    }
                }
            }
            mutableState.update { it.copy(isBrowseLoading = false, isBrowseLoadingMore = false) }
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
