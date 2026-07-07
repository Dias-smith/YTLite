package com.ytlite.player.data.network

object InnerTubeConfig {
    const val API_KEY = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8"
    const val BASE_URL = "https://www.youtube.com"

    val FEED_CLIENT = InnerTubeClientType.WEB

    const val HL = "en"
    const val GL = "US"

    const val USER_AGENT =
        "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"

    const val BROWSE_ID_HOME = "FEwhat_to_watch"
    const val BROWSE_ID_LIBRARY = "FEmy_youtube"

    val BROWSE_URL: String
        get() = "$BASE_URL/youtubei/v1/browse?key=$API_KEY"

    val SEARCH_URL: String
        get() = "$BASE_URL/youtubei/v1/search?key=$API_KEY"
}
