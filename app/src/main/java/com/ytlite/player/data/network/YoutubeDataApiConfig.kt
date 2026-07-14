package com.ytlite.player.data.network

object YoutubeDataApiConfig {
    const val BASE_URL = "https://www.googleapis.com/youtube/v3"
    const val CHANNELS_LIST_URL = "$BASE_URL/channels"
    const val SUBSCRIPTIONS_LIST_URL = "$BASE_URL/subscriptions"
    const val ACTIVITIES_LIST_URL = "$BASE_URL/activities"
    const val SEARCH_LIST_URL = "$BASE_URL/search"
    const val PLAYLIST_ITEMS_LIST_URL = "$BASE_URL/playlistItems"
    const val PLAYLISTS_LIST_URL = "$BASE_URL/playlists"
    const val VIDEOS_LIST_URL = "$BASE_URL/videos"

    /** Music category for videos.list chart=mostPopular */
    const val VIDEO_CATEGORY_MUSIC = "10"

    const val HOT_KEYWORDS_LIMIT = 10

    /**
     * Dedicated Data API key for Search hot keywords (mostPopular Music).
     */
    const val HOT_KEYWORDS_API_KEY = "AIzaSyAbMOfstY2zu-C9zxHBbtXRh9ybYcbpeYc"

    fun mostPopularMusicVideosUrl(maxResults: Int = HOT_KEYWORDS_LIMIT): String =
        "$VIDEOS_LIST_URL" +
            "?part=snippet" +
            "&chart=mostPopular" +
            "&videoCategoryId=$VIDEO_CATEGORY_MUSIC" +
            "&maxResults=$maxResults" +
            "&key=$HOT_KEYWORDS_API_KEY"
}
