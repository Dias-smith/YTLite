package com.ytlite.player.data.repository

import android.content.Context
import android.util.Log
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
import com.ytlite.player.data.network.YouTubeHttpClient
import com.ytlite.player.data.network.YoutubeDataApiConfig
import com.ytlite.player.data.parser.BrowsePage
import com.ytlite.player.data.parser.BrowseParser
import com.ytlite.player.data.parser.SearchResultParser
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.withContext
import org.json.JSONObject

class SearchRepository(
    context: Context,
    private val innerTubeApi: InnerTubeApi = InnerTubeApi.getInstance(),
    private val httpClient: YouTubeHttpClient = YouTubeHttpClient.getInstance(),
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

    /**
     * Hot keywords from YouTube Data API v3 mostPopular Music videos (titles).
     * Uses an in-process TTL cache to avoid refetching on every Search tab visit.
     */
    suspend fun fetchHotKeywords(limit: Int = YoutubeDataApiConfig.HOT_KEYWORDS_LIMIT): List<String> =
        withContext(Dispatchers.IO) {
            val now = System.currentTimeMillis()
            synchronized(hotKeywordsLock) {
                val cached = hotKeywordsCache
                if (cached != null && now - cached.fetchedAtMs < HOT_KEYWORDS_TTL_MS) {
                    return@withContext cached.keywords
                }
            }
            val derived = try {
                fetchYoutubeMostPopularMusicTitles(limit)
            } catch (e: Exception) {
                Log.e(TAG, "fetchHotKeywords failed", e)
                emptyList()
            }
            if (derived.isNotEmpty()) {
                synchronized(hotKeywordsLock) {
                    hotKeywordsCache = HotKeywordsCache(derived, now)
                }
            } else {
                Log.w(TAG, "fetchHotKeywords: no keywords derived")
            }
            derived
        }

    private fun fetchYoutubeMostPopularMusicTitles(limit: Int): List<String> {
        val result = httpClient.request(
            url = YoutubeDataApiConfig.mostPopularMusicVideosUrl(maxResults = limit),
            method = "GET",
            headers = emptyMap(),
            body = null,
        )
        if (!result.success || result.result.isNullOrBlank()) {
            Log.w(TAG, "videos.list mostPopular failed code=${result.errCode} msg=${result.errMsg}")
            return emptyList()
        }
        val items = JSONObject(result.result).optJSONArray("items") ?: return emptyList()
        val titles = ArrayList<String>(limit)
        val seen = LinkedHashSet<String>()
        for (index in 0 until items.length()) {
            if (titles.size >= limit) break
            val title = items.optJSONObject(index)
                ?.optJSONObject("snippet")
                ?.optString("title")
                ?.trim()
                ?.replace(Regex("\\s+"), " ")
                ?.takeIf { it.isNotBlank() }
                ?: continue
            if (!seen.add(title.lowercase())) continue
            titles.add(title)
        }
        return titles
    }

    suspend fun fetchPlaylistVideos(
        playlistId: String,
        continuation: String? = null,
    ): BrowsePage = withContext(Dispatchers.IO) {
        runCatching {
            val response = innerTubeApi.browsePlaylistItems(playlistId, continuation)
            BrowseParser.parseVideoList(response)
        }.getOrElse { BrowsePage() }
    }

    suspend fun fetchBrowseVideos(
        browseId: String,
        continuation: String? = null,
    ): BrowsePage = withContext(Dispatchers.IO) {
        runCatching {
            val response = innerTubeApi.browseExplore(browseId, continuation = continuation)
            BrowseParser.parseVideoList(response)
        }.getOrElse { BrowsePage() }
    }

    companion object {
        private const val TAG = "SearchRepository"
        private const val HOT_KEYWORDS_TTL_MS = 3 * 60 * 60 * 1000L // 3 hours

        private data class HotKeywordsCache(
            val keywords: List<String>,
            val fetchedAtMs: Long,
        )

        private val hotKeywordsLock = Any()

        @Volatile
        private var hotKeywordsCache: HotKeywordsCache? = null

        @Volatile
        private var instance: SearchRepository? = null

        fun getInstance(context: Context): SearchRepository =
            instance ?: synchronized(this) {
                instance ?: SearchRepository(context.applicationContext).also { instance = it }
            }
    }
}
