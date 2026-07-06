package com.ytlite.player.ui.home

import androidx.annotation.StringRes
import androidx.compose.runtime.Immutable
import com.ytlite.player.R

@Immutable
data class FeedCategory(
    val id: String,
    @param:StringRes val labelRes: Int,
    val searchQuery: String? = null,
)

object HomeCategories {
    const val ALL_ID = "all"

    val items: List<FeedCategory> = listOf(
        FeedCategory(ALL_ID, R.string.home_category_all),
        FeedCategory("music", R.string.home_category_music, "music"),
        FeedCategory("ai", R.string.home_category_ai, "AI"),
        FeedCategory("playlists", R.string.home_category_playlists, "playlists"),
        FeedCategory("podcasts", R.string.home_category_podcasts, "podcasts"),
        FeedCategory("web_pages", R.string.home_category_web_pages, "web pages"),
        FeedCategory("live", R.string.home_category_live, "live"),
        FeedCategory("apple", R.string.home_category_apple, "Apple"),
        FeedCategory("firebase", R.string.home_category_firebase, "Firebase"),
        FeedCategory("gaming", R.string.home_category_gaming, "gaming"),
        FeedCategory("dance_pop", R.string.home_category_dance_pop, "dance pop"),
        FeedCategory("graphic_design", R.string.home_category_graphic_design, "graphic design"),
        FeedCategory("variety_shows", R.string.home_category_variety_shows, "variety shows"),
        FeedCategory("art", R.string.home_category_art, "art"),
        FeedCategory("recently_uploaded", R.string.home_category_recently_uploaded, "recently uploaded"),
        FeedCategory("new_to_you", R.string.home_category_new_to_you, "recommended"),
    )

    fun find(id: String): FeedCategory? = items.firstOrNull { it.id == id }
}
