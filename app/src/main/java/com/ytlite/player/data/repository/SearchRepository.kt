package com.ytlite.player.data.repository

import android.content.Context
import com.ytlite.player.data.local.YTLiteDatabase
import com.ytlite.player.data.local.entity.SearchQueryEntity
import com.ytlite.player.data.local.entity.SearchRecentClickEntity
import com.ytlite.player.data.model.DiscoveryType
import com.ytlite.player.data.model.SearchRecentType
import com.ytlite.player.data.model.SearchResultPage
import com.ytlite.player.data.model.SearchResultTab
import com.ytlite.player.data.model.SearchSuggestion
import com.ytlite.player.data.network.InnerTubeApi
import com.ytlite.player.data.network.InnerTubeConfig
import com.ytlite.player.data.parser.BrowsePage
import com.ytlite.player.data.parser.BrowseParser
import com.ytlite.player.data.parser.SearchResultParser
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.withContext

class SearchRepository(
    context: Context,
    private val innerTubeApi: InnerTubeApi = InnerTubeApi.getInstance(),
) {
    private val searchQueryDao = YTLiteDatabase.getInstance(context).searchQueryDao()
    private val recentClickDao = YTLiteDatabase.getInstance(context).searchRecentClickDao()

    fun observeQueryHistory(): Flow<List<SearchQueryEntity>> = searchQueryDao.observeRecentQueries()

    fun observeRecentClicks(): Flow<List<SearchRecentClickEntity>> = recentClickDao.observeRecentClicks()

    suspend fun saveQuery(query: String) = withContext(Dispatchers.IO) {
        val trimmed = query.trim()
        if (trimmed.isBlank()) return@withContext
        searchQueryDao.upsert(SearchQueryEntity(query = trimmed))
        searchQueryDao.trimToLimit()
    }

    suspend fun clearQueryHistory() = withContext(Dispatchers.IO) {
        searchQueryDao.clearAll()
    }

    suspend fun recordRecentClick(
        targetId: String,
        type: SearchRecentType,
        title: String,
        subtitle: String = "",
        thumbnailUrl: String = "",
    ) = withContext(Dispatchers.IO) {
        recentClickDao.upsert(
            SearchRecentClickEntity(
                targetId = targetId,
                type = type.name,
                title = title,
                subtitle = subtitle,
                thumbnailUrl = thumbnailUrl,
            ),
        )
    }

    suspend fun deleteRecentClick(targetId: String) = withContext(Dispatchers.IO) {
        recentClickDao.deleteById(targetId)
    }

    suspend fun clearRecentClicks() = withContext(Dispatchers.IO) {
        recentClickDao.clearAll()
    }

    suspend fun fetchSuggestions(query: String, historyQueries: List<String>): List<SearchSuggestion> =
        withContext(Dispatchers.IO) {
            if (query.isBlank()) return@withContext emptyList()
            runCatching {
                val response = innerTubeApi.search(query)
                SearchResultParser.parseSuggestions(response, query, historyQueries)
            }.getOrElse { emptyList() }
        }

    suspend fun search(
        query: String,
        tab: SearchResultTab,
        continuation: String? = null,
    ): SearchResultPage = withContext(Dispatchers.IO) {
        val params = when (tab) {
            SearchResultTab.ALL -> null
            SearchResultTab.VIDEOS -> InnerTubeConfig.SEARCH_PARAMS_VIDEOS
            SearchResultTab.CHANNELS -> InnerTubeConfig.SEARCH_PARAMS_CHANNELS
            SearchResultTab.PLAYLISTS -> InnerTubeConfig.SEARCH_PARAMS_PLAYLISTS
        }
        val response = innerTubeApi.search(query, params, continuation)
        SearchResultParser.parseResults(response, tab)
    }

    suspend fun browseDiscovery(type: DiscoveryType): BrowsePage = withContext(Dispatchers.IO) {
        val browseId = when (type) {
            DiscoveryType.NEW_RELEASES -> InnerTubeConfig.BROWSE_ID_TRENDING
            DiscoveryType.CHARTS -> InnerTubeConfig.BROWSE_ID_CHARTS
            DiscoveryType.MOODS_AND_GENRES -> InnerTubeConfig.BROWSE_ID_EXPLORE
        }
        runCatching {
            val response = innerTubeApi.browseExplore(browseId)
            BrowseParser.parse(response, type)
        }.getOrElse { BrowsePage() }
    }

    companion object {
        @Volatile
        private var instance: SearchRepository? = null

        fun getInstance(context: Context): SearchRepository =
            instance ?: synchronized(this) {
                instance ?: SearchRepository(context.applicationContext).also { instance = it }
            }
    }
}
