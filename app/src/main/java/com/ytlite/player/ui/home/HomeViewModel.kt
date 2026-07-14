package com.ytlite.player.ui.home

import android.app.Application
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.ytlite.player.data.cache.HomeFeedCache
import com.ytlite.player.data.cache.toHomeFeedPage
import com.ytlite.player.data.model.ExtractionResult
import com.ytlite.player.data.model.HomeFeedItem
import com.ytlite.player.data.model.HomeFeedPage
import com.ytlite.player.data.preferences.HomePreferences
import com.ytlite.player.data.repository.ExtractionRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class HomeViewModel(
    private val repository: ExtractionRepository,
    private val homePreferences: HomePreferences,
    private val homeFeedCache: HomeFeedCache,
) : ViewModel() {

    private val _uiState = MutableStateFlow(HomeUiState())
    val uiState: StateFlow<HomeUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            val savedId = homePreferences.getSelectedCategoryId()
            val category = HomeCategories.find(savedId.orEmpty())
                ?: HomeCategories.items.first()
            _uiState.update { it.copy(selectedCategoryId = category.id) }
            loadFeedForCategory(category, preferCache = true)
        }
    }

    fun loadFeed() {
        val category = HomeCategories.find(_uiState.value.selectedCategoryId)
            ?: HomeCategories.items.first()
        loadFeedForCategory(category, preferCache = true)
    }

    fun refresh() {
        val category = HomeCategories.find(_uiState.value.selectedCategoryId)
            ?: HomeCategories.items.first()
        loadFeedForCategory(category, preferCache = false)
    }

    fun selectCategory(categoryId: String) {
        if (categoryId == _uiState.value.selectedCategoryId) return
        val category = HomeCategories.find(categoryId) ?: return
        _uiState.update {
            it.copy(
                selectedCategoryId = categoryId,
                albumBrowse = null,
            )
        }
        viewModelScope.launch {
            homePreferences.setSelectedCategoryId(categoryId)
        }
        loadFeedForCategory(category, preferCache = true)
    }

    fun loadMore() {
        val state = _uiState.value
        val token = state.continuation ?: return
        if (state.isLoadingMore || state.isLoading) return
        val categoryId = state.selectedCategoryId

        viewModelScope.launch {
            _uiState.update { it.copy(isLoadingMore = true) }
            val result = if (state.feedSearchQuery == ExtractionRepository.FEED_QUERY_MUSIC_NEW_RELEASES) {
                repository.fetchMusicNewReleaseAlbumsFeed(
                    offset = ExtractionRepository.parseNewReleaseOffset(token),
                )
            } else {
                when (
                    val pageResult = repository.fetchHomeFeedContinuation(
                        continuation = token,
                        searchQuery = state.feedSearchQuery,
                    )
                ) {
                    is ExtractionResult.Success -> ExtractionResult.Success(
                        HomeFeedPage(
                            items = pageResult.data.videos.map { HomeFeedItem.Track(it) },
                            continuation = pageResult.data.continuation,
                        ),
                    )
                    is ExtractionResult.Error -> pageResult
                }
            }
            when (result) {
                is ExtractionResult.Success -> {
                    val merged = (_uiState.value.items + result.data.items).distinctBy { it.id }
                    val page = HomeFeedPage(
                        items = merged,
                        continuation = result.data.continuation,
                    )
                    _uiState.update { current ->
                        current.copy(
                            items = merged,
                            continuation = result.data.continuation,
                            isLoadingMore = false,
                        )
                    }
                    if (categoryId == _uiState.value.selectedCategoryId) {
                        homeFeedCache.write(
                            categoryId = categoryId,
                            page = page,
                            feedSearchQuery = _uiState.value.feedSearchQuery,
                        )
                    }
                }
                is ExtractionResult.Error -> {
                    _uiState.update { it.copy(isLoadingMore = false) }
                }
            }
        }
    }

    fun openAlbum(album: HomeFeedItem.Album) {
        _uiState.update {
            it.copy(
                albumBrowse = AlbumBrowseState(
                    album = album,
                    isLoading = true,
                    errorMessage = null,
                ),
            )
        }
        viewModelScope.launch {
            when (
                val result = repository.fetchMusicAlbumTracks(
                    browseId = album.browseId,
                    albumTitle = album.title,
                    artistFallback = album.artistName,
                    thumbnailFallback = album.thumbnailUrl,
                )
            ) {
                is ExtractionResult.Success -> {
                    _uiState.update { current ->
                        current.copy(
                            albumBrowse = current.albumBrowse?.copy(
                                tracks = result.data,
                                isLoading = false,
                                errorMessage = null,
                            ),
                        )
                    }
                }
                is ExtractionResult.Error -> {
                    _uiState.update { current ->
                        current.copy(
                            albumBrowse = current.albumBrowse?.copy(
                                isLoading = false,
                                errorMessage = result.message,
                            ),
                        )
                    }
                }
            }
        }
    }

    fun closeAlbumBrowse() {
        _uiState.update { it.copy(albumBrowse = null) }
    }

    fun refreshAlbumBrowse() {
        val album = _uiState.value.albumBrowse?.album ?: return
        openAlbum(album)
    }

    private fun loadFeedForCategory(category: FeedCategory, preferCache: Boolean) {
        viewModelScope.launch {
            val requestId = category.id
            if (preferCache) {
                val cached = homeFeedCache.read(category.id)
                if (cached != null && cached.items.isNotEmpty()) {
                    val page = cached.toHomeFeedPage()
                    _uiState.update {
                        it.copy(
                            selectedCategoryId = category.id,
                            items = page.items,
                            continuation = page.continuation,
                            feedSearchQuery = cached.feedSearchQuery ?: feedSearchQueryFor(category),
                            isLoading = false,
                            errorMessage = null,
                            albumBrowse = null,
                        )
                    }
                    homePreferences.setSelectedCategoryId(category.id)
                    // Use cache only — no automatic network refresh.
                    return@launch
                }
            }

            _uiState.update {
                it.copy(
                    isLoading = true,
                    errorMessage = null,
                    items = emptyList(),
                    continuation = null,
                    albumBrowse = null,
                )
            }

            val network = fetchFeedPage(category)
            if (_uiState.value.selectedCategoryId != requestId) return@launch

            when (network) {
                is ExtractionResult.Success -> {
                    val feedSearchQuery = feedSearchQueryFor(category)
                    _uiState.update {
                        it.copy(
                            items = network.data.items,
                            continuation = network.data.continuation,
                            feedSearchQuery = feedSearchQuery,
                            isLoading = false,
                            errorMessage = null,
                        )
                    }
                    homeFeedCache.write(
                        categoryId = category.id,
                        page = network.data,
                        feedSearchQuery = feedSearchQuery,
                    )
                    homePreferences.setSelectedCategoryId(category.id)
                }
                is ExtractionResult.Error -> {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            errorMessage = network.message,
                        )
                    }
                }
            }
        }
    }

    private suspend fun fetchFeedPage(category: FeedCategory): ExtractionResult<HomeFeedPage> {
        return when (category.source) {
            FeedCategorySource.MusicNewReleaseAlbums ->
                repository.fetchMusicNewReleaseAlbumsFeed()
            FeedCategorySource.Search -> when (
                val result = repository.fetchHomeFeed(searchQuery = category.searchQuery)
            ) {
                is ExtractionResult.Success -> ExtractionResult.Success(
                    HomeFeedPage(
                        items = result.data.videos.map { HomeFeedItem.Track(it) },
                        continuation = result.data.continuation,
                    ),
                )
                is ExtractionResult.Error -> result
            }
        }
    }

    private fun feedSearchQueryFor(category: FeedCategory): String? =
        when (category.source) {
            FeedCategorySource.MusicNewReleaseAlbums ->
                ExtractionRepository.FEED_QUERY_MUSIC_NEW_RELEASES
            FeedCategorySource.Search -> category.searchQuery
        }

    companion object {
        fun factory(application: Application): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                HomeViewModel(
                    repository = ExtractionRepository.getInstance(),
                    homePreferences = HomePreferences.getInstance(application),
                    homeFeedCache = HomeFeedCache.getInstance(application),
                )
            }
        }
    }
}
