package com.ytlite.player.data.model

sealed interface SearchScreenState {
    data object DefaultHub : SearchScreenState
    data class Suggestions(val query: String) : SearchScreenState
    data class Results(val query: String, val tab: SearchResultTab = SearchResultTab.ALL) : SearchScreenState
    data class SubCategory(val type: DiscoveryType) : SearchScreenState
    data class BrowseVideos(
        val browseId: String,
        val title: String,
        val kind: BrowseVideosKind,
    ) : SearchScreenState
}

enum class BrowseVideosKind {
    PLAYLIST,
    MOOD,
}

enum class SearchResultTab {
    ALL,
    VIDEOS,
    CHANNELS,
    PLAYLISTS,
}

enum class DiscoveryType {
    NEW_RELEASES,
    CHARTS,
    MOODS_AND_GENRES,
}

enum class SearchRecentType {
    VIDEO,
    CHANNEL,
    PLAYLIST,
}
