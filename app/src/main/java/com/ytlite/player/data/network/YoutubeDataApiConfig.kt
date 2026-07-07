package com.ytlite.player.data.network

object YoutubeDataApiConfig {
    const val BASE_URL = "https://www.googleapis.com/youtube/v3"
    const val SUBSCRIPTIONS_LIST_URL = "$BASE_URL/subscriptions"
    const val ACTIVITIES_LIST_URL = "$BASE_URL/activities"
    const val SEARCH_LIST_URL = "$BASE_URL/search"
    const val PLAYLIST_ITEMS_LIST_URL = "$BASE_URL/playlistItems"
}
