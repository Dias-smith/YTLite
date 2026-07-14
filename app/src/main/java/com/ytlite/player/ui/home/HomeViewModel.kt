package com.ytlite.player.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ytlite.player.data.model.ExtractionResult
import com.ytlite.player.data.model.HomeFeedItem
import com.ytlite.player.data.repository.ExtractionRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class HomeViewModel(
    private val repository: ExtractionRepository = ExtractionRepository.getInstance(),
) : ViewModel() {

    private val _uiState = MutableStateFlow(HomeUiState())
    val uiState: StateFlow<HomeUiState> = _uiState.asStateFlow()

    init {
        loadFeed()
    }

    fun loadFeed() {
        val category = HomeCategories.find(_uiState.value.selectedCategoryId)
            ?: HomeCategories.items.first()
        loadFeedForCategory(category)
    }

    fun refresh() {
        val category = HomeCategories.find(_uiState.value.selectedCategoryId)
            ?: HomeCategories.items.first()
        loadFeedForCategory(category)
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
        loadFeedForCategory(category)
    }

    fun loadMore() {
        val state = _uiState.value
        val token = state.continuation ?: return
        if (state.isLoadingMore || state.isLoading) return

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
                        com.ytlite.player.data.model.HomeFeedPage(
                            items = pageResult.data.videos.map { HomeFeedItem.Track(it) },
                            continuation = pageResult.data.continuation,
                        ),
                    )
                    is ExtractionResult.Error -> pageResult
                }
            }
            when (result) {
                is ExtractionResult.Success -> {
                    _uiState.update { current ->
                        val merged = (current.items + result.data.items)
                            .distinctBy { it.id }
                        current.copy(
                            items = merged,
                            continuation = result.data.continuation,
                            isLoadingMore = false,
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

    private fun loadFeedForCategory(category: FeedCategory) {
        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isLoading = true,
                    errorMessage = null,
                    items = emptyList(),
                    continuation = null,
                    albumBrowse = null,
                )
            }
            when (category.source) {
                FeedCategorySource.MusicNewReleaseAlbums -> {
                    when (val result = repository.fetchMusicNewReleaseAlbumsFeed()) {
                        is ExtractionResult.Success -> {
                            _uiState.update {
                                it.copy(
                                    items = result.data.items,
                                    continuation = result.data.continuation,
                                    feedSearchQuery =
                                        ExtractionRepository.FEED_QUERY_MUSIC_NEW_RELEASES,
                                    isLoading = false,
                                    errorMessage = null,
                                )
                            }
                        }
                        is ExtractionResult.Error -> {
                            _uiState.update {
                                it.copy(
                                    isLoading = false,
                                    errorMessage = result.message,
                                )
                            }
                        }
                    }
                }
                FeedCategorySource.Search -> {
                    when (val result = repository.fetchHomeFeed(searchQuery = category.searchQuery)) {
                        is ExtractionResult.Success -> {
                            _uiState.update {
                                it.copy(
                                    items = result.data.videos.map { video ->
                                        HomeFeedItem.Track(video)
                                    },
                                    continuation = result.data.continuation,
                                    feedSearchQuery = category.searchQuery,
                                    isLoading = false,
                                    errorMessage = null,
                                )
                            }
                        }
                        is ExtractionResult.Error -> {
                            _uiState.update {
                                it.copy(
                                    isLoading = false,
                                    errorMessage = result.message,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
