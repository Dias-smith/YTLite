package com.ytlite.player.ui.home

import androidx.annotation.StringRes
import androidx.compose.runtime.Immutable
import com.ytlite.player.R

enum class FeedCategorySource {
    Search,
    MusicNewReleaseAlbums,
}

@Immutable
data class FeedCategory(
    val id: String,
    @param:StringRes val labelRes: Int,
    val searchQuery: String? = null,
    val source: FeedCategorySource = FeedCategorySource.Search,
)

object HomeCategories {
    val items: List<FeedCategory> = listOf(
        FeedCategory(
            id = "all",
            labelRes = R.string.home_category_all,
            searchQuery = null,
        ),
        FeedCategory(
            id = "new_release",
            labelRes = R.string.home_category_new_release,
            source = FeedCategorySource.MusicNewReleaseAlbums,
        ),
        FeedCategory("podcasts", R.string.home_category_podcasts, "podcasts"),
        FeedCategory("energize", R.string.home_category_energize, "energize music"),
        FeedCategory("feel_good", R.string.home_category_feel_good, "feel good music"),
        FeedCategory("workout", R.string.home_category_workout, "workout music"),
        FeedCategory("chill", R.string.home_category_chill, "chill music"),
        FeedCategory("party", R.string.home_category_party, "party music"),
        FeedCategory("romance", R.string.home_category_romance, "romance music"),
        FeedCategory("commute", R.string.home_category_commute, "commute music"),
        FeedCategory("focus", R.string.home_category_focus, "focus music"),
        FeedCategory("sad", R.string.home_category_sad, "sad music"),
        FeedCategory("sleep", R.string.home_category_sleep, "sleep music"),
    )

    val defaultId: String = items.first().id

    fun find(id: String): FeedCategory? = items.firstOrNull { it.id == id }
}
